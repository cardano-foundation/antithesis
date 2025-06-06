## Antithesis scenario

### Context
  * `alice` is a user who wants to run tests in Antithesis
     * `alice` github user holds a maintainer role in the repository `IntersectMBO/cardano-node-test`
     * `alice` has registered an ssh ed25519 pub key in her github profile
  * code to setup an Antithesis test lives in repository `IntersectMBO/cardano-node-test`
  * `antithesis` is an agent that controls and monitors test-run's on the antithesis platform
  * `token` is a stateful uninque token locked on-chain tracking the interactions between `alice` and `antithesis`. As a side effect it tracks also alice github credentials and alice github roles. It's a fact container, with a smart contract controlling the update process of the facts.
  * `oracle` is an agent in charge of the `token` updates. It does everything in its power to prevent inconsistent data to enter/exit the `token`.

### Alice state journey
```mermaid
%%{init: {"themeVariables": {"fontSize": "9px"}}}%%

stateDiagram-v2
    [*] --> Unregistered
    Unregistered --> RegisteringUser: anti register-user command
    RegisteringUser --> RegisteredUser: alice credential from token observation
    RegisteredUser --> RegisteringRole: anti register-role command
    RegisteringRole --> RegisteredMaintainer: alice roles from token observation
    RegisteredMaintainer --> RequestingTestRun: anti request-test-run
    RequestingTestRun --> AwaitingTestRunOutcome: test-run rejected from token observation
    AwaitingTestRunOutcome --> RegisteredMaintainer: test-run accepted from token observation
    RequestingTestRun --> RegisteredMaintainer: test-run results from token observation
```

### Antithesis agent state journey
```mermaid
%%{init: {"themeVariables": {"fontSize": "9px"}}}%%

stateDiagram-v2
    [*] --> Idle
    Idle --> EvaluatingRequest: test-run request from token observation
    EvaluatingRequest --> RejectingRequest: fail to match request requirements
    EvaluatingRequest --> AcceptingRequest: matches request requirements
    RejectingRequest --> Idle: anti reject-test-run command
    AcceptingRequest --> ProcessingTestRun: anti accept-test-run command
    ProcessingTestRun --> ReportingResults: request results from antithesis platform observation
    ReportingResults --> Idle: anti response-test-run command
```

### Oracle state journey

```mermaid
%%{init: {"themeVariables": {"fontSize": "9px"}}}%%

stateDiagram-v2
    direction LR
    [*] --> Idle
    Idle --> ProcessingUserRegistration: Receives anti register-user
    Idle --> ProcessingRoleRegistration: Receives anti register-role
    Idle --> ProcessingTestRunRequest: Receives anti request-test-run
    Idle --> ProcessingTestRunRejection: Receives anti reject-test-run
    Idle --> ProcessingTestRunAcceptance: Receives anti accept-test-run
    Idle --> ProcessingTestRunResults: Receives anti response-test-run

    ProcessingUserRegistration --> MergingFact: GitHub attests credentials
    ProcessingUserRegistration --> Idle: GitHub rejects credentials
    ProcessingRoleRegistration --> MergingFact: Token and GitHub attest role
    ProcessingRoleRegistration --> Idle: Token or GitHub rejects role
    ProcessingTestRunRequest --> MergingFact: Token attests maintainer and valid index
    ProcessingTestRunRequest --> Idle: Token rejects request
    ProcessingTestRunRejection --> MergingFact: Antithesis identity and request state valid
    ProcessingTestRunRejection --> Idle: Invalid identity or state
    ProcessingTestRunAcceptance --> MergingFact: Antithesis identity and request state valid
    ProcessingTestRunAcceptance --> Idle: Invalid identity or state
    ProcessingTestRunResults --> MergingFact: Antithesis identity and progress state valid
    ProcessingTestRunResults --> Idle: Invalid identity or state

    MergingFact --> Idle: Token fact merged
```

### Workflow



```mermaid
sequenceDiagram
    actor Alice

    participant GitHub as Github Platform
        actor Oracle
        participant Token as Cardano Token
    actor Antithesis
    participant AntithesisP as Antithesis Platform


    %% Step 1: Alice registers as an identified user
    Alice->>+Oracle: anti register-user --platform github --username alice --pubkeyhash ${pkh}
    Oracle->>+GitHub: Verify alice credentials
    GitHub-->>-Oracle: Credentials attested
    Oracle->>+Token: Merge fact {platform/username: {public_key: AAAAC3...}}
    Token-->>-Oracle: Fact merged
    Alice->>+Token: Poll (anti query --username alice)
    Token-->>-Alice: Identity registered

    %% Step 2: Alice registers role as maintainer
    Alice->>+Oracle: anti register-role --platform github --repository IntersectMBO/cardano-node-test --username alice --role maintainer
    Oracle->>+Token: Check alice credentials
    Token-->>-Oracle: Credentials attested
    Oracle->>+GitHub: Verify alice role
    GitHub-->>-Oracle: Role attested
    Oracle->>+Token: Merge fact {platform/repo/maintainer: {username: alice}}
    Token-->>-Oracle: Fact merged
    Alice->>+Token: Poll (anti query --username alice)
    Token-->>-Alice: Role registered

    %% Step 3: Alice requests test run
    loop alice requests for
    Alice->>+Oracle: anti request-test-run --platform github --repository IntersectMBO/cardano-node-test --commit 234456 --username alice
    Oracle->>+Token: Check alice is maintainer
    Token-->>-Oracle: Maintainer attested
    Oracle->>+Token: Check platform/repo/commit prefix and run-index
    Token-->>-Oracle: Valid index
    Oracle->>+Token: Merge fact {platform/repo/commit/test-run/run-index: {state: request, conditions: {timeout: 1d}}}
    Token-->>-Oracle: Fact merged

    %% Step 4: Antithesis processes test run request
    Antithesis->>+Token: Poll for test-run requests
    Token-->>-Antithesis: Request found
    alt Antithesis rejects request
        Antithesis->>+Oracle: anti reject-test-run --platform github --repository IntersectMBO/cardano-node-test --commit 234456
        Oracle->>+Token: Verify antithesis identity and request state
        Token-->>-Oracle: Valid
        Oracle->>+Token: Merge fact {platform/repo/commit/test-run/run-index: {state: rejected}}
        Token-->>-Oracle: Fact merged
    else Antithesis accepts request
        Antithesis->>+Oracle: anti accept-test-run --platform github --repository IntersectMBO/cardano-node-test --commit 234456
        Oracle->>+Token: Verify antithesis identity and request state
        Token-->>-Oracle: Valid
        Oracle->>+Token: Merge fact {platform/repo/commit/test-run/run-index: {state: accepted}}
        Token-->>-Oracle: Fact merged
    end

    %% Step 5: Antithesis updates test run results
    Antithesis->>+AntithesisP: Poll platform for test results
    AntithesisP->>+Antithesis: Test results
    Antithesis->>+Oracle: anti response-test-run --platform github --repository IntersectMBO/cardano-node-test --commit 234456 --ipfs cbe89a...
    Oracle->>+Token: Verify antithesis identity and progress state
    Token-->>-Oracle: Valid
    Oracle->>+Token: Merge fact {platform/repo/commit/test-run/run-index: {state: finished, results: cbe89a...}}
    Token-->>-Oracle: Fact merged
    end
```
