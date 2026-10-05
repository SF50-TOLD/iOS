/// The instructions a stock model reads before every NOTAM.
///
/// Field-level rules live in ``NOTAMExtraction``'s `@Guide` descriptions, which the framework includes
/// in the prompt as the response schema; these instructions carry the rules of `SCHEMA.md` that span
/// fields. They are model input, not user-facing text, so they are not localized.
enum StockModelInstructions {
  static let text = """
    You read one NOTAM for a pilot of a Cirrus SF50 Vision Jet (a light, single-engine, fixed-wing \
    jet: 6,000 lb, 39 ft wingspan) and record the runway-performance facts it states.

    Rules:
    - Record only what the text states. If a fact is not stated, use null. Never derive, compute, \
    convert or guess a value. Numbers lose thousands separators; fractions become decimals (1/8IN \
    is 0.125 in).
    - Units: use the unit written on the value or in its table header. A declared-distance table \
    with no unit takes the unit the same NOTAM uses for runway length or threshold displacement \
    (AVBL LEN 990M, DTHR 210M); if those are mixed or absent, the distances are null. In a US \
    NOTAM (location starting K, PA, PH, PG, PW or TJ, or an FAA identifier like BZN or 64S) that \
    gives no unit for heights or elevations, they are feet. Otherwise a value with no unit is null.
    - Effects: one effect per runway direction, zero-padded ("9R" is "09R"). A fact stated for a \
    pair such as RWY 09/27 is recorded on an effect for 09 and an effect for 27, each with the \
    same values. Every fact about one direction goes in that direction's one effect. Use runway \
    null only for the aerodrome or all runways.
    - Closures: CLSD, CLOSED or NOT AVBL is both. CLSD FOR LDG, LDG NOT AUTH is landing; CLSD FOR \
    TKOF is takeoff. AVBL FOR TKOF ONLY means closed for landing, and the reverse. A closure with \
    exceptions (EXC PPR) or to a class that includes the SF50 (CLSD TO JET TFC, CLSD TO FIXED WING \
    ACFT) reads as written. A closure only to a class that excludes the SF50 (over 12,500 lb, \
    helicopters), only at stated times (CLSD DLY 2200-0600), or only for IFR is none.
    - A direction closed for both records no partial closure, threshold displacement or declared \
    distances. TORA is null when closed for takeoff; LDA is null when closed for landing.
    - Partial closure: a closed portion of a direction. Its end is thresholdEnd for FIRST, \
    departureEnd for LAST, a compass abbreviation (NORTH END is N), or a runway end. When FIRST or \
    LAST is given against a pair, or the position is relative to a taxiway, the end is null.
    - Threshold displacement includes a relocated threshold. For a further displacement, record \
    only a stated total.
    - Declared distances: record only TORA and LDA as labelled; never copy one into the other. \
    Declared distances that name no runway belong to the only runway direction the NOTAM names; if \
    it names several, or only a pair, leave them out. AVBL LEN, EFFECTIVE OPR LENGTH and distances \
    from a taxiway intersection are not declared distances.
    - Surface condition (FICON, RSC, SNOWTAM): rwyCC lists the codes as reported. List each \
    distinct contaminant once, even when several thirds report it. DRY is no contaminant. Ignore \
    treatments (SANDED, DEICED), cleared width, REMAINDER contaminants, friction values and \
    braking action. A SNOWTAM gives coverage in percent and depth in mm; NR is null.
    - Obstacles: a physical object near the aerodrome with a height or position, including \
    heliport obstacles and temporary obstacles an obstacle departure procedure (ODP) adds. Height \
    datum is MSL for MSL, AMSL, ELEV or ELEVATION, and AGL for AGL, HEIGHT or HGT; when both are \
    stated record MSL, and in "<n>FT (<n>FT AGL)" the first is MSL. Reference: departureEnd for \
    DER, DEP END or BEYOND TORA RWY xx; threshold for THR or APCH END; ARP for ARP or the airport \
    identifier ("2.2NM WNW JFK"); other for anything else. Direction is a compass word or a stated \
    bearing in degrees (RDL 114); RIGHT OF CENTERLINE is null.
    - If the text says NOTAMC, CANCELED, CANCELLED or CNL, set isCanceled to true and record no \
    effects or obstacles.

    Record nothing for: lighting; navaids; taxiway or apron items, including their FICONs; \
    helipads and water lanes; procedure or minima changes, and obstacles named in approach (IAP) \
    or minima NOTAMs; published obstacles listed in ODP takeoff notes; obstacles that exist only \
    under a condition; en-route obstacle lists; hours, services and airspace; markings and signs; \
    a threshold no longer displaced; declared distances "as published"; a runway fact given only \
    as the reason (DUE ...) for something else.
    """
}
