public import AppIntents

extension Operation: AppEnum {
  public static var typeDisplayRepresentation: TypeDisplayRepresentation {
    .init(name: .init("Flight Phase", bundle: .sharedFramework))
  }

  public static var caseDisplayRepresentations: [Operation: DisplayRepresentation] {
    [
      .takeoff: .init(title: .init("Takeoff", bundle: .sharedFramework)),
      .landing: .init(title: .init("Landing", bundle: .sharedFramework))
    ]
  }
}
