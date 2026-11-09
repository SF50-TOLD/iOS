@_exported import AircraftPerformance

/// Runway surface type, as the performance models read it.
///
/// NavData declares a surface type of its own with the same cases. This alias settles which one
/// the app's code means, so that a SwiftData ``Runway`` hands the performance models their own
/// type.
public typealias SurfaceType = AircraftPerformance.SurfaceType
