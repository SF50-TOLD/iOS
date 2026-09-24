/// The instructions the on-device model reads before every NOTAM.
///
/// Field-level rules live in ``NOTAMExtraction``'s `@Guide` descriptions, which the framework includes in the
/// prompt as the response schema; these instructions carry only the rules that span fields. They are model
/// input, not user-facing text, so they are not localized.
enum NOTAMExtractionInstructions {
  static let text = """
    You read one NOTAM for a pilot of a Cirrus SF50 Vision Jet (a light, single-engine, fixed-wing \
    jet: 6,000 lb, 39 ft wingspan) and record the runway-performance facts it states.

    Rules:
    - Record only what the text states. If a fact is not stated, use null. Never derive, compute, \
    convert or guess a value.
    - A value's unit is the one written on the value or in its table header. A declared-distance \
    table with no unit takes the unit the same NOTAM uses for runway length or threshold \
    displacement (AVBL LEN 990M, DTHR 210M); if those are mixed or absent, the distances are null. \
    In a US NOTAM (location starting K, PA, PH, PG, PW or TJ, or an FAA identifier like BZN or \
    64S) that gives no unit for any height or elevation, heights and elevations are feet. \
    Otherwise a value with no unit is null.
    - Obstacle heights: HEIGHT or HGT is above ground (AGL); ELEVATION or ELEV is above sea level \
    (MSL).
    - Runway designators are written as in the text, zero-padded ("9R" becomes "09R"). Write a \
    runway pair with a slash ("09R/27L").
    - Make one effect per designator. If the text gives a closure for a runway pair and declared \
    distances for each direction, make one effect for the pair carrying the closure, and one \
    effect per direction with closure "none" carrying its declared distances.
    - Declared distances given for a runway pair ("RWY12R/30L LDA 320M") apply to each direction: \
    one effect per direction, each with the same values. Declared distances that name no runway \
    belong to the one runway direction the NOTAM names; if it names more than one runway, or only \
    a pair such as "RWY 09/27", leave them out. Distances from an intersection ("DIST FROM TWY B") \
    are not declared distances.
    - A relocated threshold ("THR RELOCATED 1040FT") is a threshold displacement.
    - A runway closed to a class of aircraft that includes the SF50 ("CLSD TO JET TFC", "CLSD TO \
    FIXED WING ACFT") is a full closure. A closure only to a class that excludes it (over 12,500 \
    lb, wingspan over 118 ft, helicopters) is not.
    - If the text says NOTAMC, CANCELED, CANCELLED or CNL, set isCanceled to true and return no \
    effects.
    - FICON: rwyCC lists the codes as reported. Commas separate runway thirds; give each \
    contaminant its third, 1 to 3 in reporting order. Ignore treatments (SANDED, DEICED), cleared \
    width, REMAINDER contaminants and braking action.
    - Obstacles: record obstacles near the aerodrome, including heliports and obstacles in \
    departure procedures (ODP). Convert a stated DMS position to decimal degrees. Never use Q-line \
    coordinates.

    Return no effects for: lighting; ILS or navaid outages; taxiway or apron items, including \
    taxiway or apron FICONs; helipad and water-lane items; procedure or minima changes; hours and \
    services; airspace; obstacle-light outages; markings and signs; closures only to a class of \
    aircraft that excludes the SF50; a threshold no longer displaced; declared distances "as \
    published"; obstacles named in approach procedure (IAP) or minima NOTAMs; obstacles that exist \
    only under a stated condition ("ONLY WHEN RAISED").
    """
}
