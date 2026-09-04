import Foundation
import Testing

@testable import SF50_Shared

struct ValueArithmeticTests {

  // MARK: - Addition

  @Test
  func `adding two definite values`() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .value(50)
    let result = a + b
    #expect(result == .value(150))
  }

  @Test
  func `adding value and scalar`() {
    let a: Value<Double> = .value(100)
    let result = a + 25.0
    #expect(result == .value(125))
  }

  @Test
  func `adding definite value to value with uncertainty`() {
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

  @Test
  func `adding uncertain value to definite value`() {
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

  @Test
  func `adding two uncertain values propagates RSS uncertainty`() {
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

  @Test
  func `adding scalar to uncertain value preserves uncertainty`() {
    var a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    a += 10.0
    if case .valueWithUncertainty(let v, let u) = a {
      #expect(v == 110)
      #expect(u == 3)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(a)")
    }
  }

  @Test
  func `adding invalid propagates invalid`() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .invalid
    #expect(a + b == .invalid)
  }

  @Test
  func `adding offscaleHigh propagates offscaleHigh`() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .offscaleHigh
    #expect(a + b == .offscaleHigh)
  }

  // MARK: - Subtraction

  @Test
  func `subtracting two definite values`() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .value(30)
    let result = a - b
    #expect(result == .value(70))
  }

  @Test
  func `subtracting scalar from value`() {
    let a: Value<Double> = .value(100)
    let result = a - 25.0
    #expect(result == .value(75))
  }

  @Test
  func `subtracting two uncertain values propagates RSS uncertainty`() {
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

  @Test
  func `subtracting definite from uncertain preserves uncertainty`() {
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

  @Test
  func `subtracting uncertain from definite gets RHS uncertainty`() {
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

  @Test
  func `subtracting scalar from uncertain value preserves uncertainty`() {
    var a: Value<Double> = .valueWithUncertainty(100, uncertainty: 3)
    a -= 10.0
    if case .valueWithUncertainty(let v, let u) = a {
      #expect(v == 90)
      #expect(u == 3)
    } else {
      Issue.record("Expected .valueWithUncertainty, got \(a)")
    }
  }

  @Test
  func `subtracting invalid propagates invalid`() {
    let a: Value<Double> = .value(100)
    let b: Value<Double> = .invalid
    #expect(a - b == .invalid)
  }

  // MARK: - Subtraction then addition (contamination pattern)

  @Test
  func `contamination pattern: distance + (contaminatedRun - baseRun)`() {
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

  @Test
  func `+= with two values`() {
    var a: Value<Double> = .value(100)
    a += Value.value(50)
    #expect(a == .value(150))
  }

  @Test
  func `-= with two values`() {
    var a: Value<Double> = .value(100)
    a -= Value.value(30)
    #expect(a == .value(70))
  }
}
