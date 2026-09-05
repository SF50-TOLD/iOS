public import AppIntents

extension Operation: AppEnum {
  public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Flight Phase" }

  public static var caseDisplayRepresentations: [Operation: DisplayRepresentation] {
    [
      .takeoff: .init(title: "Takeoff"),
      .landing: .init(title: "Landing")
    ]
  }
}
