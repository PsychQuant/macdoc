// ProperNounList.swift — Common proper nouns for title case → sentence case conversion
// Used by APAUtilities.protectProperNouns and title normalization to preserve proper nouns
// when converting Title Case to sentence case.
import Foundation

public struct ProperNounList {

    /// Set of common proper nouns that should remain capitalized in sentence case.
    /// Includes: country/territory names, nationality/language adjectives,
    /// continent names, and academic derived terms (eponyms).
    public static let all: Set<String> = {
        var set = Set<String>()
        set.formUnion(countries)
        set.formUnion(nationalities)
        set.formUnion(continents)
        set.formUnion(eponyms)
        set.formUnion(religions)
        set.formUnion(historicalPeriods)
        return set
    }()

    /// Check if a word is a known proper noun (case-insensitive lookup, returns true if match)
    public static func isProperNoun(_ word: String) -> Bool {
        // Strip trailing punctuation for lookup
        let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
        return all.contains(cleaned)
    }

    // MARK: - Country & Territory Names (ISO 3166 + common variants)

    static let countries: Set<String> = [
        // A
        "Afghanistan", "Albania", "Algeria", "Andorra", "Angola", "Argentina",
        "Armenia", "Australia", "Austria", "Azerbaijan",
        // B
        "Bahamas", "Bahrain", "Bangladesh", "Barbados", "Belarus", "Belgium",
        "Belize", "Benin", "Bhutan", "Bolivia", "Bosnia", "Botswana", "Brazil",
        "Brunei", "Bulgaria", "Burkina", "Burundi",
        // C
        "Cambodia", "Cameroon", "Canada", "Chad", "Chile", "China", "Colombia",
        "Comoros", "Congo", "Croatia", "Cuba", "Cyprus", "Czechia",
        // D
        "Denmark", "Djibouti", "Dominica", "Dominican",
        // E
        "Ecuador", "Egypt", "El Salvador", "England", "Equatorial", "Eritrea",
        "Estonia", "Eswatini", "Ethiopia",
        // F
        "Fiji", "Finland", "France",
        // G
        "Gabon", "Gambia", "Georgia", "Germany", "Ghana", "Greece", "Grenada",
        "Guatemala", "Guinea", "Guyana",
        // H
        "Haiti", "Honduras", "Hungary",
        // I
        "Iceland", "India", "Indonesia", "Iran", "Iraq", "Ireland", "Israel",
        "Italy",
        // J
        "Jamaica", "Japan", "Jordan",
        // K
        "Kazakhstan", "Kenya", "Kiribati", "Korea", "Kosovo", "Kuwait",
        "Kyrgyzstan",
        // L
        "Laos", "Latvia", "Lebanon", "Lesotho", "Liberia", "Libya",
        "Liechtenstein", "Lithuania", "Luxembourg",
        // M
        "Madagascar", "Malawi", "Malaysia", "Maldives", "Mali", "Malta",
        "Mauritania", "Mauritius", "Mexico", "Micronesia", "Moldova", "Monaco",
        "Mongolia", "Montenegro", "Morocco", "Mozambique", "Myanmar",
        // N
        "Namibia", "Nauru", "Nepal", "Netherlands", "Nicaragua", "Niger",
        "Nigeria", "Norway",
        // O
        "Oman",
        // P
        "Pakistan", "Palau", "Palestine", "Panama", "Paraguay", "Peru",
        "Philippines", "Poland", "Portugal",
        // Q
        "Qatar",
        // R
        "Romania", "Russia", "Rwanda",
        // S
        "Samoa", "Sao", "Saudi", "Scotland", "Senegal", "Serbia", "Seychelles",
        "Sierra", "Singapore", "Slovakia", "Slovenia", "Solomon", "Somalia",
        "South", "Spain", "Sri", "Sudan", "Suriname", "Sweden", "Switzerland",
        "Syria",
        // T
        "Taiwan", "Tajikistan", "Tanzania", "Thailand", "Togo", "Tonga",
        "Trinidad", "Tunisia", "Turkey", "Turkmenistan", "Tuvalu",
        // U
        "Uganda", "Ukraine", "United", "Uruguay", "Uzbekistan",
        // V
        "Vanuatu", "Vatican", "Venezuela", "Vietnam",
        // W
        "Wales",
        // Y
        "Yemen",
        // Z
        "Zambia", "Zimbabwe",

        // Common multi-word handled as single words when split
        "Africa", "America", "Americas", "Arabia", "Asia", "Britain",
        "Caribbean", "Europe", "Hong Kong", "Kong", "Lanka", "Lucia",
        "New Zealand", "Zealand", "Rica", "Leone", "Vincent", "Verde",
        "Tome", "Principe", "Marino", "Kitts", "Nevis", "Tobago",
        "Grenadines", "Timor", "Leste", "Pacific", "Atlantic",
        "Arctic", "Antarctic", "Mediterranean", "Sahara", "Sahel",
    ]

    // MARK: - Nationality & Language Adjectives

    static let nationalities: Set<String> = [
        "Afghan", "African", "Albanian", "Algerian", "American", "Angolan",
        "Arab", "Arabic", "Argentine", "Argentinian", "Armenian", "Asian",
        "Australian", "Austrian", "Azerbaijani",
        "Bahamian", "Bahraini", "Bangladeshi", "Barbadian", "Belarusian",
        "Belgian", "Belizean", "Beninese", "Bhutanese", "Bolivian", "Bosnian",
        "Brazilian", "British", "Bruneian", "Bulgarian", "Burmese", "Burundian",
        "Cambodian", "Cameroonian", "Canadian", "Chadian", "Chilean", "Chinese",
        "Colombian", "Congolese", "Costa", "Rican", "Croatian", "Cuban",
        "Cypriot", "Czech",
        "Danish", "Dominican", "Dutch",
        "Ecuadorian", "Egyptian", "English", "Equatorial", "Eritrean",
        "Estonian", "Ethiopian", "European",
        "Fijian", "Filipino", "Finnish", "French",
        "Gabonese", "Gambian", "Georgian", "German", "Ghanaian", "Greek",
        "Grenadian", "Guatemalan", "Guinean", "Guyanese",
        "Haitian", "Honduran", "Hungarian",
        "Icelandic", "Indian", "Indonesian", "Iranian", "Iraqi", "Irish",
        "Israeli", "Italian",
        "Jamaican", "Japanese", "Jordanian",
        "Kazakh", "Kenyan", "Korean", "Kurdish", "Kuwaiti", "Kyrgyz",
        "Laotian", "Latvian", "Lebanese", "Liberian", "Libyan", "Lithuanian",
        "Luxembourgish",
        "Macedonian", "Malagasy", "Malawian", "Malaysian", "Maldivian",
        "Malian", "Maltese", "Mauritanian", "Mauritian", "Mexican", "Moldovan",
        "Mongolian", "Montenegrin", "Moroccan", "Mozambican",
        "Namibian", "Nepalese", "Nicaraguan", "Nigerian", "Norwegian",
        "Omani",
        "Pakistani", "Palestinian", "Panamanian", "Paraguayan", "Peruvian",
        "Philippine", "Polish", "Portuguese",
        "Qatari",
        "Romanian", "Russian", "Rwandan",
        "Samoan", "Saudi", "Scottish", "Senegalese", "Serbian", "Singaporean",
        "Slovak", "Slovenian", "Somali", "Spanish", "Sudanese", "Surinamese",
        "Swedish", "Swiss", "Syrian",
        "Taiwanese", "Tajik", "Tanzanian", "Thai", "Togolese", "Tongan",
        "Trinidadian", "Tunisian", "Turkish", "Turkmen",
        "Ugandan", "Ukrainian", "Uruguayan", "Uzbek",
        "Venezuelan", "Vietnamese",
        "Welsh",
        "Yemeni",
        "Zambian", "Zimbabwean",

        // Major languages (that are also adjectives)
        "Afrikaans", "Amharic", "Bengali", "Cantonese", "Catalan",
        "Dari", "Farsi", "Gaelic", "Gujarati", "Hausa", "Hebrew",
        "Hindi", "Igbo", "Javanese", "Kannada", "Khmer",
        "Lao", "Latin", "Malay", "Malayalam", "Mandarin", "Marathi",
        "Oriya", "Pashto", "Punjabi", "Quechua", "Sanskrit",
        "Serbian", "Sinhalese", "Somali", "Swahili", "Tagalog", "Tamil",
        "Telugu", "Thai", "Tibetan", "Tigrinya", "Urdu",
        "Wolof", "Xhosa", "Yoruba", "Zulu",
    ]

    // MARK: - Continents & Major Regions

    static let continents: Set<String> = [
        "Africa", "Antarctica", "Asia", "Australia", "Australasia",
        "Oceania", "Europe", "Eurasia",
        "Scandinavia", "Polynesia", "Melanesia", "Micronesia",
        "Mesopotamia", "Balkans", "Caucasus", "Iberia",
        "Patagonia", "Siberia", "Manchuria",
    ]

    // MARK: - Academic Eponyms & Derived Terms

    static let eponyms: Set<String> = [
        // Statistics & Mathematics
        "Bayesian", "Boolean", "Cartesian", "Euclidean", "Fourier",
        "Gaussian", "Hamiltonian", "Hermitian", "Hilbert", "Jacobian",
        "Lagrangian", "Laplacian", "Leibnizian", "Markov", "Markovian",
        "Newtonian", "Poisson", "Riemannian", "Thurstonian", "Turing", "Wiener",
        "Bernoulli", "Chebyshev", "Dirichlet", "Euler", "Galois",
        "Gödel", "Hausdorff", "Kolmogorov", "Lebesgue", "Lyapunov",
        "Mandelbrot", "Monte Carlo", "Nash", "Pareto", "Pearson",
        "Shannon", "Wald", "Weibull",

        // Physics
        "Einsteinian", "Heisenberg", "Maxwellian", "Planck", "Schrödinger",
        "Boltzmann", "Coulomb", "Doppler", "Faraday", "Fermi",
        "Kelvin", "Lorentz", "Ohmic", "Rayleigh", "Tesla",

        // Psychology & Social Sciences
        "Freudian", "Jungian", "Lacanian", "Pavlovian", "Piagetian",
        "Rogerian", "Skinnerian", "Vygotskian", "Eriksonian", "Adlerian",
        "Beckian", "Chomskyan", "Darwinian", "Deweyian", "Foucauldian",
        "Gramscian", "Hegelian", "Hobbesian", "Kantian", "Keynesian",
        "Kuhnian", "Lockean", "Machiavellian", "Malthusian", "Marxian",
        "Marxist", "Nietzschean", "Platonic", "Rawlsian", "Ricardian",
        "Rousseauian", "Smithian", "Socratic", "Weberian", "Wittgensteinian",
        "Aristotelian", "Augustinian", "Thomistic", "Cartesian",

        // Biology & Medicine
        "Mendelian", "Lamarckian", "Linnaean", "Hippocratic", "Galenic",
        "Pasteurian", "Krebs", "Golgi", "Broca", "Wernicke",

        // Named effects, laws, tests (person names used as modifiers)
        "Likert", "Thurstone", "Cronbach", "Cohen", "Bonferroni", "Tukey",
        "Fisher", "Student", "Wilcoxon", "Mann", "Whitney",
        "Kruskal", "Wallis", "Shapiro", "Wilk", "Levene",
        "Durbin", "Watson", "Granger", "Hausman", "Tobit",
        "Probit", "Logit",

        // Computing & Technology
        "Boolean", "Turing", "Von Neumann", "Dijkstra",
        "Huffman", "Knuth",
    ]

    // MARK: - Religions & Philosophical Traditions

    static let religions: Set<String> = [
        "Buddhist", "Buddhism", "Catholic", "Catholicism",
        "Christian", "Christianity", "Confucian", "Confucianism",
        "Hindu", "Hinduism", "Islamic", "Islam", "Jain", "Jainism",
        "Jewish", "Judaism", "Mormon", "Mormonism",
        "Muslim", "Orthodox", "Protestant", "Protestantism",
        "Quaker", "Shinto", "Shintoism", "Sikh", "Sikhism",
        "Sufi", "Sufism", "Sunni", "Shia", "Taoist", "Taoism",
        "Zen", "Zoroastrian",
    ]

    // MARK: - Historical Periods & Movements

    static let historicalPeriods: Set<String> = [
        "Renaissance", "Enlightenment", "Reformation", "Baroque",
        "Byzantine", "Victorian", "Edwardian", "Elizabethan",
        "Jacobean", "Tudor", "Stuart", "Meiji", "Qing", "Ming",
        "Ottoman", "Habsburg", "Mughal", "Roman", "Greek",
        "Medieval", "Romanesque", "Gothic", "Rococo",
        "Impressionist", "Impressionism", "Surrealist", "Surrealism",
        "Cubist", "Cubism", "Dadaist", "Dadaism",
        "Modernist", "Modernism", "Postmodernist", "Postmodernism",
        "Structuralist", "Structuralism",
        "Poststructuralist", "Poststructuralism",
        "Existentialist", "Existentialism",
        "Stoic", "Stoicism", "Epicurean", "Epicureanism",
        "Utilitarian", "Utilitarianism",
        "Neoclassical", "Neoliberal", "Neoliberalism",
        "Romanticism", "Romantic",
        "Cold War", "Antebellum", "Reconstruction",
        "Napoleonic", "Jacksonian", "Jeffersonian", "Wilsonian",
        "Thatcherism", "Reaganomics",
    ]
}
