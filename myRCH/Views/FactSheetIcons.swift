import SwiftUI

// Icons for fact sheets and their categories, picked from the words in the
// title, so a list reads at a glance: a thermometer for fever, lungs for
// croup. The site has no pictures for its sheets.

extension FactSheet {
    /// Words in the title (and its other names) and the icon they suggest,
    /// most specific first: "Hand, foot and mouth disease" is a hand, not a
    /// mouth; "Head injuries" a head, not first aid.
    private static let iconRules: [(words: [String], symbol: String)] = [
        (["hand, foot", "hand foot"], "hand.raised.fill"),
        (["penis", "foreskin", "testes", "testic", "scrot", "circumcis", "hypospadias", "genital"], "figure.child"),
        (["bedwet", "wetting"], "drop.fill"),
        (["head injur", "concussion", "brain", "cerebral", "amnesia", "seizure", "epilep", "headache", "migraine", "dystonia"], "brain.head.profile.fill"),
        (["fever", "temperature"], "thermometer.medium"),
        (["cough", "croup", "asthma", "bronchi", "pneumonia", "wheez", "breath", "lung", "respirat", "whooping", "cpap", "airway", "tracheost"], "lungs.fill"),
        (["cleft", "palate"], "mouth.fill"),
        (["conjunctivitis", "eye", "vision", "squint"], "eye.fill"),
        (["ear ", "ears", "hearing", "glue ear", "otitis", "grommet"], "ear.fill"),
        (["nose", "nosebleed", "sinus"], "nose.fill"),
        (["teeth", "tooth", "dental", "tongue", "mouth", "tonsil", "adenoid"], "mouth.fill"),
        (["worm", "lice", "scabies", "head lice", "insect", "bite", "sting"], "ladybug.fill"),
        (["burn", "scald", "sunburn"], "flame.fill"),
        (["allerg", "anaphyla", "hay fever", "hives", "urticaria"], "allergens"),
        (["vaccin", "immunis", "injection", "needle", "cvad", "catheter", "picc", "infusion", "cannula"], "syringe.fill"),
        (["medicine", "paracetamol", "ibuprofen", "antibiotic", "pain relief", "pain-relief", "dose", "clonidine", "rituximab", "creatine"], "pills.fill"),
        (["molluscum", "eczema", "rash", "skin", "acne", "pimple", "wart", "birthmark", "dermat", "dermal", "dermoid", "impetigo", "nappy", "cradle cap", "scar", "keloid", "port wine"], "hand.raised.fingers.spread.fill"),
        (["virus", "viral", "infection", "flu", "covid", "chickenpox", "measles", "gastro", "meningo", "strep", "sepsis", "germ", "hepatitis"], "microbe.fill"),
        (["constipation", "tummy", "abdominal", "vomit", "diarrh", "reflux", "bowel", "toilet", "poo", "pyloric", "appendic", "anorectal", "colonic"], "toilet.fill"),
        (["urine", "urinary", "bladder", "kidney", "diabet", "blood sugar", "adrenal"], "drop.fill"),
        (["blood", "anaemia", "iron", "bleed", "haemophilia"], "drop.halffull"),
        (["heart", "cardiac", "murmur"], "heart.fill"),
        (["fracture", "broken", "sprain", "plaster", "cast", "bone", "joint", "hip", "limp", "spine", "scoliosis", "knee", "ankle", "wrist", "elbow", "crutch", "rickets", "ctev", "ddh", "brachial"], "figure.walk"),
        (["palsy", "dystrophy", "wheelchair", "disabilit"], "figure.roll"),
        (["mental", "anxiety", "depress", "stress", "mood", "self-harm", "suicid", "wellbeing", "distressing", "fatigue"], "brain.filled.head.profile"),
        (["behaviour", "tantrum", "autism", "adhd", "attention", "bully"], "face.smiling.inverse"),
        (["sleep", "settling", "bedtime", "night"], "moon.zzz.fill"),
        (["baby", "babies", "newborn", "infant", "breastfe", "bottle", "wrapping", "swaddl"], "stroller.fill"),
        (["food", "nutrition", "eating", "diet", "weight", "fussy"], "fork.knife"),
        (["vap", "smok", "alcohol", "drug"], "smoke.fill"),
        (["screen", "social media", "online", "gaming"], "iphone"),
        (["exercise", "active", "sport", "physical activity"], "figure.run"),
        (["safety", "car seat", "drown", "poison", "choking", "falls", "sun safety"], "shield.lefthalf.filled"),
        (["first aid", "emergency", "cpr", "wound", "cut", "graze", "splinter", "laceration"], "cross.case.fill"),
        (["surgery", "operation", "anaesthe", "day surgery", "discharge", "post-op", "stitches", "delirium", "aneurysm"], "scissors"),
        (["x-ray", "scan", "mri", "ultrasound", "test", "eeg", "ecg", "biopsy", "endoscop", "colonoscop", "dexa", "manometry"], "testtube.2"),
        (["speech", "language", "talking", "stutter", "communication", "dysarthria"], "text.bubble.fill"),
        (["period", "menstru", "contracep", "pregnan", "puberty", "sexual", "sti", "vulv"], "heart.text.square.fill"),
        (["hospital", "health system", "appointment", "gp", "telehealth", "stay", "education", "school"], "building.2.fill"),
        (["video"], "video.fill"),
    ]

    /// Worked out once per sheet; lists of hundreds redraw often.
    @MainActor private static var iconCache: [URL: String] = [:]

    /// An icon that suggests what the sheet's about, or a page when nothing
    /// in the title matches. Words match only at the start of a word, so
    /// "cut" isn't found in "acute", or "hip" in "relationship".
    var systemImage: String {
        if let cached = Self.iconCache[url] { return cached }
        let text = ([title] + aliases).joined(separator: " ").lowercased()
        let symbol = Self.iconRules.first { rule in
            rule.words.contains { word in
                text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word), options: .regularExpression) != nil
            }
        }?.symbol ?? "doc.text.fill"
        Self.iconCache[url] = symbol
        return symbol
    }
}

extension FactSheetCategory {
    /// An icon and colour per category, like Browse's tiles. Unknown
    /// categories get a folder in the library's colour.
    func style(in library: FactSheet.Library) -> (symbol: String, color: Color) {
        let name = name.lowercased()
        let styles: [(words: [String], symbol: String, color: Color)] = [
            (["allerg"], "allergens", .orange),
            (["behaviour"], "face.smiling.inverse", .yellow),
            (["blood"], "drop.fill", .red),
            (["bone", "orthopaed"], "figure.walk", .brown),
            (["brain"], "brain.head.profile.fill", .pink),
            (["burn"], "flame.fill", .orange),
            (["day surgery", "surgery", "plastic"], "scissors", .indigo),
            (["dermat", "skin"], "hand.raised.fingers.spread.fill", .mint),
            (["emergency"], "staroflife.fill", .red),
            (["first aid"], "cross.case.fill", .red),
            (["general"], "stethoscope", Theme.brand),
            (["heart"], "heart.fill", .red),
            (["infection"], "microbe.fill", .green),
            (["medicine"], "pills.fill", .teal),
            (["mental"], "brain.filled.head.profile", .purple),
            (["health system", "services"], "building.2.fill", .blue),
            (["neurolog"], "brain.fill", .pink),
            (["nutrition"], "fork.knife", .green),
            (["respirat"], "lungs.fill", .cyan),
            (["rehab"], "figure.roll", .indigo),
            (["safety"], "shield.lefthalf.filled", .orange),
            (["sexual", "women"], "heart.text.square.fill", .pink),
            (["speech"], "text.bubble.fill", .teal),
            (["teen"], "figure.wave", .purple),
            (["test", "procedure"], "testtube.2", .blue),
            (["urolog"], "drop.halffull", .yellow),
            (["video"], "video.fill", .gray),
        ]
        if let style = styles.first(where: { $0.words.contains(where: name.contains) }) {
            return (style.symbol, style.color)
        }
        return ("folder.fill", library.color)
    }
}
