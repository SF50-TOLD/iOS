import Foundation
import Testing

@testable import SF50_Shared

struct ValueArithmeticTests {

  // MARK: - Addition

  @Test("Adding two definite values")
  func addValues() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .value(50)
    let result = a + b
    #expect(result == .value(150))
  }

  @Test("Adding value and scalar")
  func addScalar() {
    let a: Value<Double> = .value(100)
    let result = a + 25.0
    #expect(result == .value(125))
  }

  @Test("Adding definite value to value with uncertainty")
  func addValueToUncertain() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .valueWithUncertainty(50, uncertainty: 5)
    let result = a + b
    if case .valueWithUncertainty(let v, let u) = result {
      #expect(v == 150)
      #expect(u == 5)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(result)")
    }
  }

  @Test("Adding uncertain value to definite value")
  func addUncertainToValue() {
    let a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    let b: Value<Double> = .value(50)
    let result = a + b
    if case .valueWithUncertainty(let v, let u) = result {
      #expect(v == 150)
      #expect(u == 3)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(result)")
    }
  }

  @Test("Adding two uncertain values propagates RSS uncertainty")
  func addTwoUncertain() {
    let a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    let b: Value<Double> = .valueWithUncertainty(50, uncertainty: 4)
    let result = a + b
    if case .valueWithUncertainty(let v, let u) = result {
      #expect(v == 150)
      #expect(abs(u - 5) < 1e-10)  // sqrt(9 + 16) = 5
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(result)")
    }
  }

  @Test("Adding scalar to uncertain value preserves uncertainty")
  func addScalarToUncertain() {
    var a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    a += 10.0
    if case .valueWithUncertainty(let v, let u) = a {
      #expect(v == 110)
      #expect(u == 3)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(a)")
    }
  }

  @Test("Adding invalid propagates invalid")
  func addInvalid() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .invalid
    #expect(a + b == .invalid)
  }

  @Test("Adding offscaleHigh propagates offscaleHigh")
  func addOffscaleHigh() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .offscaleHigh
    #expect(a + b == .offscaleHigh)
  }

  // MARK: - Subtraction

  @Test("Subtracting two definite values")
  func subtractValues() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .value(30)
    let result = a - b
    #expect(result == .value(70))
  }

  @Test("Subtracting scalar from value")
  func subtractScalar() {
    let a: Value<Double> = .value(100)
    let result = a - 25.0
    #expect(result == .value(75))
  }

  @Test("Subtracting two uncertain values propagates RSS uncertainty")
  func subtractTwoUncertain() {
    let a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    let b: Value<Double> = .valueWithUncertainty(30, uncertainty: 4)
    let result = a - b
    if case .valueWithUncertainty(let v, let u) = result {
      #expect(v == 70)
      #expect(abs(u - 5) < 1e-10)  // sqrt(9 + 16) = 5
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(result)")
    }
  }

  @Test("Subtracting definite from uncertain preserves uncertainty")
  func subtractValueFromUncertain() {
    let a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    let b: Value<Double> = .value(30)
    let result = a - b
    if case .valueWithUncertainty(let v, let u) = result {
      #expect(v == 70)
      #expect(u == 3)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(result)")
    }
  }

  @Test("Subtracting uncertain from definite gets RHS uncertainty")
  func subtractUncertainFromValue() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .valueWithUncertainty(30, uncertainty: 4)
    let result = a - b
    if case .valueWithUncertainty(let v, let u) = result {
      #expect(v == 70)
      #expect(u == 4)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(result)")
    }
  }

  @Test("Subtracting scalar from uncertain value preserves uncertainty")
  func subtractScalarFromUncertain() {
    var a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    a -= 10.0
    if case .valueWithUncertainty(let v, let u) = a {
      #expect(v == 90)
      #expect(u == 3)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(a)")
    }
  }

  @Test("Subtracting invalid propagates invalid")
  func subtractInvalid() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .invalid
    #expect(a - b == .invalid)
  }

  // MARK: - Subtraction then addition (contamination pattern)

  @Test("Contamination pattern: distance + (contaminatedRun - baseRun)")
  func contaminationPattern() {
    let baseDistance: Value<Double> = .value(2000)
    let baseRun: Value<Double> = .value(1000)
    let contaminatedRun: Value<Double> = .valueWithUncertainty(1300, uncertainty: 20)

    let runIncrease = contaminatedRun - baseRun
    let result = baseDistance + runIncrease

    if case .valueWithUncertainty(let v, let u) = result {
      #expect(v == 2300)
      #expect(u == 20)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(result)")
    }
  }

  // MARK: - Compound Assignment

  @Test("+= with two values")
  func addAssign() {
    var a: Value<Double> = .value(100)
    a += Value.value(50)
    #expect(a == .value(150))
  }

  @Test("-= with two values")
  func subtractAssign() {
    var a: Value<Double> = .value(100)
    a -= Value.value(30)
    #expect(a == .value(70))
  }
}
