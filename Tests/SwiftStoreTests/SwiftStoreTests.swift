import Testing
@testable import SwiftStore

struct TestState: AppState, Equatable {
  var count: Int = 0
}

enum TestAction: AppAction {
  case increment
  case decrement
}

@Sendable
func TestReducer(state: TestState, action: AppAction) -> TestState {
  var state = state

  switch action {
    case TestAction.increment:
      state.count += 1

    case TestAction.decrement:
      state.count -= 1

    default:
      break
  }

  return state
}

@Test("Dispatch updates state")
func dispatchUpdatesState() async {
  let store = await Store<TestState>(
    initialState: TestState(),
    reducer: TestReducer
  )

  await store.dispatch(TestAction.increment)
  await store.dispatch(TestAction.increment)

  let state = await store.getState()

  #expect(state.count == 2)
}

@Test("Dispatch preserves order")
func dispatchOrderIsPreserved() async {
  let store = await Store<TestState>(
    initialState: TestState(),
    reducer: TestReducer
  )

  await store.dispatch(TestAction.increment)
  await store.dispatch(TestAction.increment)
  await store.dispatch(TestAction.decrement)

  let state = await store.getState()

  #expect(state.count == 1)
}

@Test("Middleware is invoked")
func middlewareIsInvoked() async {
  let middleware: Middleware<TestState> = { store, action, _, _ in
    switch (action) {
      case TestAction.increment:
        await store.dispatch(TestAction.decrement)
        
      default:
        break
    }
  }

  let store = await Store<TestState>(
    initialState: TestState(),
    reducer: TestReducer,
    middlewares: [middleware]
  )

  await store.dispatch(TestAction.increment)
  
  let state = await store.getState()

  #expect(state.count == 0)
}

@Test("Thunk dispatches actions")
func thunkDispatchesActions() async {
  let store = await Store<TestState>(
    initialState: TestState(),
    reducer: TestReducer
  )

  let thunk: Thunk<TestState> = { store in
    await store.dispatch(TestAction.increment)
    await store.dispatch(TestAction.increment)
  }

  await store.dispatch(thunk)

  let state = await store.getState()

  #expect(state.count == 2)
}

@Test("Thunk does async work")
func asyncThunkWorks() async throws {
  let store = await Store<TestState>(
    initialState: TestState(),
    reducer: TestReducer
  )

  let thunk: Thunk<TestState> = { store in
    try? await Task.sleep(for: .milliseconds(50))
    await store.dispatch(TestAction.increment)
  }

  await store.dispatch(thunk)

  let state = await store.getState()

  #expect(state.count == 1)
}

@Test("Store is thread-safe")
func concurrentDispatchIsSafe() async {
  let store = await Store<TestState>(
    initialState: TestState(),
    reducer: TestReducer
  )

  await withTaskGroup(of: Void.self) { group in
    for _ in 0..<100 {
      group.addTask {
        await store.dispatch(TestAction.increment)
      }
    }
  }

  let state = await store.getState()

  #expect(state.count == 100)
}

@Test("Store respects initial state")
func initialStateIsRespected() async {
  let store = await Store<TestState>(
    initialState: TestState(count: 10),
    reducer: TestReducer
  )

  await store.dispatch(TestAction.increment)

  let state = await store.getState()

  #expect(state.count == 11)
}

@Test("Thunks can be postponed")
func thunksCanBePostponed() async {
  let store = await Store<TestState>(
    initialState: TestState(),
    reducer: TestReducer
  )
  
  let thunk: Thunk<TestState> = { store in
    try? await Task.sleep(for: .milliseconds(50))
    await store.dispatch(TestAction.increment)
  }

  await store.postpone(tag: "test", thunk)

  let state = await store.getState()

  #expect(state.count == 0)
  
  await store.runPostponed(tag: "test")
  
  let stateAfter = await store.getState()
  
  #expect(stateAfter.count == 1)
}
