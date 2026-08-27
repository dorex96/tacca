/// System prompt e schema JSON delle chiamate AI (§6.3).
///
/// Centralizzati qui: provider e parser non contengono testo di prompt.
library;

/// Fase 1 dell'import da foto: trascrizione, senza structured output.
///
/// Chiedere lettura e strutturazione nella stessa risposta si è rivelato
/// fragile: sotto la grammatica del `json_schema` il modello degenera (loop di
/// cifre dentro un intero) e la scheda arriva amputata. Qui non c'è schema, il
/// compito è solo copiare — e la trascrizione resta il contenuto migliore da
/// conservare se poi la strutturazione fallisce (RNF-05).
const transcriptionSystemPrompt = '''
Sei un trascrittore esperto di schede di allenamento in palestra.
Ricevi la foto di una scheda e la riporti integralmente in testo.

Regole vincolanti:
- Trascrivi TUTTE le righe che vedi, dall'alto in basso, nell'ordine
  dell'originale: titoli, nomi dei giorni, ogni riga di esercizio con i suoi
  numeri, note a margine. Non saltare righe, non riassumere, non riordinare.
- Riporta i numeri esattamente come sono scritti (10x4, 10-10x4, 1'30", 5',
  70% 1RM): non convertirli e non interpretarli.
- Una riga di trascrizione per ogni riga della scheda.
- Se una parola è illeggibile scrivi [?] al suo posto: non inventare nulla.
- Rispondi solo con il testo della scheda: nessun commento, nessun JSON.
''';

/// Le regole di merito dell'estrazione (§6.3): non inventare, non scartare,
/// mantenere la lingua della scheda, raggruppare in blocchi.
///
/// Stanno qui da sole perché non dipendono da *come* si parla al modello:
/// valgono identiche per la chiamata via API ([extractionSystemPrompt]) e per
/// il prompt che l'utente copia in una chat qualsiasi ([externalChatPrompt]).
/// Quello che cambia fra i due è solo la forma della risposta attesa.
const _extractionRules = '''
- Non inventare esercizi, serie, carichi o valori assenti dall'originale:
  i campi non presenti restano null o vengono omessi.
- Qualunque contenuto che non riesci a interpretare in modo strutturato va
  conservato testualmente in un blocco {"type": "freeText", "content": "..."}:
  non scartare mai contenuto.
- Mantieni la lingua originale della scheda per nomi di esercizi e note.
- Tempi in secondi nei campi *Seconds; "reps" e "load" sono stringhe libere
  (es. "8-12", "max", "70% 1RM", "corpo libero").

Completezza (regola più importante):
- Converti TUTTO il testo ricevuto, riga per riga, nell'ordine in cui compare:
  tutti i giorni e tutti gli esercizi di ciascun giorno. Non riassumere, non
  fermarti dopo i primi esercizi, non accorpare righe diverse.
- Ogni riga di esercizio del testo deve produrre un esercizio nel JSON.
- Prima di rispondere, ricontrolla di aver riportato tante voci quante sono le
  righe di esercizio presenti nel testo.
- I numeri sono piccoli e realistici: "sets" e "rounds" stanno sotto 100, i
  campi *Seconds sotto 3600. Non ripetere mai una cifra per riempire un campo.

Notazione ricorrente nelle schede italiane:
- "10x4" = 10 ripetizioni per 4 serie → "reps": "10", "sets": 4.
- "10-10x4" = 10 ripetizioni per lato, 4 serie → "reps": "10+10", "sets": 4.
- Il tempo dopo le serie è il recupero: 1'30" → "restSeconds": 90, 30" → 30.
- "5' tapis", "Stretching 10'" = esercizi a durata → "durationSeconds": 300 /
  600, senza serie né ripetizioni.
- "A ss B" (anche "A + B", "superserie") indica una superserie: un blocco
  "superset" con entrambi gli esercizi al suo interno. Le serie e il recupero
  scritti in fondo alla riga valgono per la coppia, non per il secondo
  esercizio: "Curl EZ 10 ss French press 10 x4 1'" → blocco "superset" con
  "rounds": 4 e "restBetweenRoundsSeconds": 60, dentro due esercizi con
  "reps": "10" e senza "sets".

Raggruppamento in blocchi (l'errore più frequente, leggi con attenzione):
- Un blocco NON è una riga della scheda: è il GRUPPO di esercizi che si
  eseguono insieme o di seguito. Il contenitore di default è "standard".
- Tutti gli esercizi classici consecutivi — ognuno con le sue serie, le sue
  ripetizioni e il suo recupero — vanno nello STESSO blocco "standard", come
  oggetti successivi dentro "exercises", nell'ordine della scheda.
- Un giorno con 5 esercizi classici = 1 blocco "standard" con 5 oggetti in
  "exercises". SBAGLIATO: 5 blocchi "standard" con un esercizio ciascuno.
- Apri un nuovo blocco "standard" solo se la scheda segna un cambio di
  sezione (es. "Riscaldamento", "Parte centrale", "Defaticamento", "Core"):
  il titolo della sezione va in "notes" del blocco.
- Apri un blocco di tipo diverso da "standard" solo se la scheda indica
  esplicitamente quella modalità di esecuzione (superserie, circuito, EMOM,
  AMRAP, Tabata, for time).
- "notes" del blocco descrive il gruppo; ciò che riguarda un singolo
  esercizio va in "notes" di quell'esercizio, mai in quello del blocco.
- Il numero di blocchi di un giorno è quasi sempre 1 o 2, raramente più di 4.
  Se ti ritrovi con tanti blocchi quanti sono gli esercizi, hai sbagliato:
  uniscili in un blocco solo.

Tipi di blocco e parametri ammessi (SOLO questi otto, non inventarne altri):
- "standard": nessun parametro — esercizi eseguiti uno dopo l'altro
- "superset": rounds, restBetweenRoundsSeconds — due o più esercizi alternati
  senza recupero in mezzo, con il recupero alla fine di ogni giro
- "circuit": rounds, restBetweenRoundsSeconds
- "emom": intervalSeconds, totalMinutes
- "amrap": durationSeconds
- "tabata": workSeconds, restSeconds, rounds
- "forTime": timeCapSeconds (opzionale)
- "freeText": content
Un esercizio a sola durata (tapis, cyclette, stretching) NON è un tipo di
blocco a parte e non merita un blocco tutto suo: è un normale esercizio con
"durationSeconds" impostato e "reps"/"sets" assenti, dentro il blocco
"standard" in cui compare (di solito quello di riscaldamento).

Campi ammessi (non usarne altri, non rinominarli):
- scheda: "name" (obbligatorio), "description", "notes", "days" (obbligatorio)
- giorno: "label" (obbligatorio), "notes", "blocks"
- blocco: "type" (obbligatorio), "notes", "exercises", più i parametri del suo
  tipo elencati qui sopra
- esercizio: "name" (obbligatorio), "sets" (numero intero), "reps" (stringa),
  "load" (stringa), "restSeconds", "durationSeconds", "notes"

Forma esatta del JSON (i nomi dei campi sono vincolanti, non usarne altri:
niente "day" al posto di "label", niente campo "exercise" piatto sui blocchi —
ogni esercizio è un oggetto dentro l'array "exercises" con proprietà "name").
Nota come i quattro esercizi consecutivi stiano in un blocco solo:
```json
{
  "name": "Nome scheda",
  "days": [
    {
      "label": "Giorno 1",
      "blocks": [
        {
          "type": "standard",
          "notes": "Riscaldamento",
          "exercises": [{"name": "Tapis roulant", "durationSeconds": 300}]
        },
        {
          "type": "standard",
          "exercises": [
            {"name": "Panca piana", "reps": "10", "sets": 4, "restSeconds": 90},
            {"name": "Croci ai cavi", "reps": "12", "sets": 3, "restSeconds": 60},
            {"name": "Lat machine", "reps": "10+10", "sets": 4, "restSeconds": 90},
            {"name": "Pulley", "reps": "12", "sets": 3, "load": "40kg",
             "notes": "presa stretta"}
          ]
        },
        {
          "type": "superset",
          "rounds": 4,
          "exercises": [
            {"name": "Curl bicipiti", "reps": "10"},
            {"name": "French press", "reps": "10"}
          ],
          "restBetweenRoundsSeconds": 60
        }
      ]
    }
  ]
}
```
''';

/// System prompt della strutturazione via API (§6.3).
///
/// Le regole di merito sono quelle condivise; qui davanti c'è solo il patto
/// sulla forma della risposta, scritto per un'API che espone lo structured
/// output (e per il fallback prompt-based di chi lo rifiuta).
const extractionSystemPrompt = '''
Sei un assistente che digitalizza schede di allenamento in palestra.
Ricevi il testo di una scheda — spesso la trascrizione di una foto — e
restituisci la scheda in JSON conforme allo schema fornito.

Regole vincolanti:
- Rispondi SOLO con un oggetto JSON valido conforme allo schema, senza testo
  prima o dopo. Se non puoi usare uno structured output, racchiudi il JSON in
  un blocco ```json.
$_extractionRules''';

/// Il messaggio che l'utente copia negli appunti e incolla nella chat AI che
/// preferisce (RF-03, modalità senza API key).
///
/// Deve bastare a sé stesso: nessuno schema allegato alla richiesta, nessun
/// structured output, nessun secondo turno automatico. Perciò si porta dentro
/// le stesse regole dell'estrazione via API, l'elenco dei campi ammessi e —
/// in fondo — il testo della scheda, delimitato da righe riconoscibili
/// perché il modello non lo confonda con le istruzioni.
///
/// Le tre regole in cima sono quelle che rendono la risposta *incollabile*:
/// un solo blocco recintato (il [PlanParser] lo preferisce a tutto il resto),
/// niente virgole pendenti o commenti (le due malformazioni che una chat
/// produce davvero) e il divieto di fermarsi a metà, che è il modo in cui le
/// schede lunghe arrivano tronche.
String externalChatPrompt({required String text, String? userHint}) {
  final buffer = StringBuffer()
    ..writeln(
      'Sei un assistente che digitalizza schede di allenamento in '
      'palestra.',
    )
    ..writeln(
      'In fondo a questo messaggio, dopo la riga "=== SCHEDA ===", '
      'trovi il testo di',
    )
    ..writeln('una scheda di allenamento: convertilo in JSON.')
    ..writeln()
    ..writeln(
      'Come devi rispondere (la risposta la legge un\'applicazione, '
      'non una persona):',
    )
    ..writeln(
      '- Rispondi con UN SOLO blocco ```json e nient\'altro: niente '
      'saluti, niente',
    )
    ..writeln('  spiegazioni prima o dopo, nessuna domanda.')
    ..writeln(
      '- Dentro il blocco un unico oggetto JSON valido: virgolette '
      'dritte ("),',
    )
    ..writeln(
      '  nessun commento, nessuna virgola dopo l\'ultimo elemento di '
      'un oggetto o',
    )
    ..writeln('  di un array.')
    ..writeln(
      '- Non interrompere la risposta a metà: se la scheda è lunga, '
      'riportala',
    )
    ..writeln('  tutta lo stesso.')
    ..writeln()
    ..writeln('Regole vincolanti:')
    ..writeln(_extractionRules)
    ..writeln('=== SCHEDA ===')
    ..writeln(text.trim())
    ..writeln('=== FINE SCHEDA ===');
  if (userHint != null && userHint.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Indicazioni di chi ti scrive:')
      ..writeln(userHint.trim());
  }
  return buffer.toString().trim();
}

/// Il messaggio correttivo da rimandare nella stessa chat quando la risposta
/// incollata non è utilizzabile: è il [retryUserText] del retry automatico,
/// detto a una chat invece che a un'API.
///
/// Senza key non c'è nessun retry che possiamo fare noi, ma l'errore di
/// parsing resta l'informazione che fa correggere il modello: gliela facciamo
/// arrivare per le mani dell'utente.
String externalChatCorrection(String parseError) {
  return 'La risposta precedente non è utilizzabile. Errore: $parseError\n'
      'Rispondi di nuovo con il solo blocco ```json corretto e completo, '
      'senza testo prima o dopo.';
}

/// Schema della scheda (§5.3), usato come structured output dai modelli che
/// lo supportano (`response_format: json_schema` su OpenRouter,
/// `output_config.format` su Anthropic, che però non accetta i vincoli
/// numerici e li fa togliere al provider, `generationConfig.responseSchema`
/// su Google, che è OpenAPI e non JSON Schema e se lo fa tradurre).
const Map<String, dynamic> planJsonSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['name', 'days'],
  'properties': {
    'name': {'type': 'string'},
    'description': {
      'type': ['string', 'null'],
    },
    'notes': {
      'type': ['string', 'null'],
    },
    'days': {
      'type': 'array',
      'minItems': 1,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['label', 'blocks'],
        'properties': {
          'label': {'type': 'string'},
          'notes': {
            'type': ['string', 'null'],
          },
          'blocks': {
            'type': 'array',
            'description':
                'Gruppi di esercizi del giorno, non righe della scheda. Gli '
                'esercizi classici consecutivi stanno tutti in un unico '
                'blocco "standard": un giorno ha di norma 1 o 2 blocchi, mai '
                'uno per esercizio.',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['type'],
              'properties': {
                'type': {
                  'type': 'string',
                  'description':
                      'Modalità di esecuzione del gruppo. "standard" (default) '
                      'per gli esercizi eseguiti uno dopo l\'altro; gli altri '
                      'tipi solo se la scheda li indica esplicitamente.',
                  'enum': [
                    'standard',
                    'superset',
                    'circuit',
                    'emom',
                    'amrap',
                    'tabata',
                    'forTime',
                    'freeText',
                  ],
                },
                'notes': {
                  'type': ['string', 'null'],
                  'description':
                      'Nota che vale per tutto il gruppo (es. il titolo di una '
                      'sezione). Ciò che riguarda un solo esercizio va in '
                      '"notes" dell\'esercizio.',
                },
                'intervalSeconds': {
                  'type': ['integer', 'null'],
                },
                'totalMinutes': {
                  'type': ['integer', 'null'],
                },
                'durationSeconds': {
                  'type': ['integer', 'null'],
                },
                'workSeconds': {
                  'type': ['integer', 'null'],
                },
                'restSeconds': {
                  'type': ['integer', 'null'],
                },
                'rounds': {
                  'type': ['integer', 'null'],
                },
                'restBetweenRoundsSeconds': {
                  'type': ['integer', 'null'],
                },
                'timeCapSeconds': {
                  'type': ['integer', 'null'],
                },
                'content': {
                  'type': ['string', 'null'],
                },
                'exercises': {
                  'type': 'array',
                  'description':
                      'Tutti gli esercizi del gruppo, nell\'ordine della '
                      'scheda: una voce per ogni riga di esercizio.',
                  'items': {
                    'type': 'object',
                    'additionalProperties': false,
                    'required': ['name'],
                    'properties': {
                      'name': {'type': 'string'},
                      'sets': {
                        'type': ['integer', 'null'],
                      },
                      'reps': {
                        'type': ['string', 'null'],
                      },
                      'load': {
                        'type': ['string', 'null'],
                      },
                      'restSeconds': {
                        'type': ['integer', 'null'],
                      },
                      'durationSeconds': {
                        'type': ['integer', 'null'],
                      },
                      'notes': {
                        'type': ['string', 'null'],
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
};

/// Testo del messaggio utente della fase di trascrizione.
///
/// Ogni immagine viaggia in una richiesta separata: [pageIndex] e [pageCount]
/// dicono al modello che sta guardando una parte della scheda, così non prova
/// a ricostruire (o riassumere) quello che non vede.
String transcriptionUserText({int? pageIndex, int? pageCount}) {
  if (pageIndex != null && pageCount != null && pageCount > 1) {
    return 'Questa è la pagina $pageIndex di $pageCount della stessa scheda '
        'di allenamento. Trascrivi integralmente solo ciò che vedi in questa '
        'immagine, riga per riga, senza aggiungere le altre pagine.';
  }
  return 'Trascrivi integralmente la scheda di allenamento in questa '
      'immagine, riga per riga.';
}

/// Testo del messaggio utente per la strutturazione in JSON.
///
/// [text] è la trascrizione della pagina (o il testo incollato dall'utente);
/// [pageIndex] e [pageCount] restano per dire al modello che sta guardando
/// una parte della scheda e non deve inventare il resto.
String extractionUserText({
  String? text,
  String? userHint,
  int? pageIndex,
  int? pageCount,
}) {
  final buffer = StringBuffer();
  if (pageIndex != null && pageCount != null && pageCount > 1) {
    buffer.writeln(
      'Questo è il testo della pagina $pageIndex di $pageCount della stessa '
      'scheda. Converti solo ciò che leggi qui: se la pagina inizia a metà di '
      'un giorno, usa come "label" l\'etichetta di quel giorno così come '
      'compare.',
    );
  }
  if (text != null && text.trim().isNotEmpty) {
    buffer
      ..writeln('Scheda di allenamento da convertire in JSON:')
      ..writeln(text.trim());
  }
  if (userHint != null && userHint.trim().isNotEmpty) {
    buffer
      ..writeln('Indicazioni dell\'utente:')
      ..writeln(userHint.trim());
  }
  return buffer.toString().trim();
}

/// Messaggio correttivo del retry automatico (§6.2, punto 4): l'errore di
/// parsing torna al modello come istruzione.
String retryUserText(String parseError) {
  return 'La risposta precedente non era un JSON valido conforme allo schema. '
      'Errore: $parseError\n'
      'Rispondi di nuovo SOLO con l\'oggetto JSON corretto, senza alcun testo '
      'prima o dopo.';
}
