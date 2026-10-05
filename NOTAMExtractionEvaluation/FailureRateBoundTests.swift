import Testing

struct `Failure-rate bounds` {
  @Test
  func `zero failures need 299 trials to bound the rate at 1%`() {
    #expect(FailureRateBound.oneSidedUpper95(failures: 0, trials: 299) <= 0.01)
    #expect(FailureRateBound.oneSidedUpper95(failures: 0, trials: 298) > 0.01)
  }

  @Test
  func `one failure needs 473 trials to bound the rate at 1%`() {
    #expect(FailureRateBound.oneSidedUpper95(failures: 1, trials: 473) <= 0.01)
    #expect(FailureRateBound.oneSidedUpper95(failures: 1, trials: 472) > 0.01)
  }

  @Test
  func `counts only passes and failures among scores`() {
    let scores = Array(repeating: 1.0, count: 299) + [-1, 0.5]
    #expect(FailureRateBound.oneSidedUpper95(scores: scores) <= 0.01)
  }
}
