# Log Book

## 2025-05-07

### Antithesis meeting

* We have new joiners in both teams!
* We discussed several topics to work on next:
  * schedule runs in CI to have regular reports overnight
  * some issue with cardano-tracer integration being restarted: all containers are defaulted (controllable only from AT side), so we need to ensure this particular container is safe to be able to haev meaningful assertions
  * Important: `sometimes` assertion only matters if they are catalogued, otherwise the report cannot tell them apart from `always` assertions
* Community engagement: It's fine if people request the CF to run some tests that are curated by us
* Discussing how we can make the environment less "dumb"
  * share Praos paper defining the adversary
* publishing and sharing blog post

#### 17:11 (db-server)

Key issue is tied to the "faults power" of the AT driver: Injecting "dumb" system-level faults leads

Some interesting property from https://eprint.iacr.org/2020/1021.pdf: Even in the face of temporary adversarial supremacy, Cardano network can recover after some time

Consensus-focused tests we could start designing & running:
* Basic property we want to ensure is that a node never crashes!
* Genesis:
  * Run cluster of nodes with genesis enabled for a while then at some point stop a node, remove its DB, restart it
  * Have a new node join later
* Utxo-hd enabled (10.4.1)
  * run a mix of nodes with lmdb and in-memory UTxO-HD enabled
  * load the system with transactions
  * There might be new race conditions due to code moving from STM to IO
  * node should restarts gracefully

Our mission should be to try very hard to crash the node, more like stress testing the system
* Just syncing a node from another node in the same container and ensuring they end up on the same chain is interesting

A simple adversarial node we could build:
* Connect to some random node
* Request arbitrary intersection along the node's chain
* Sync a little
* disconnect
* restart


### Meeting consensus team

Everyone is interested in using AT to test Consensus code, esp. as we have evidence it can find bugs ! Key issue for "deep" testing of consensus properites is tied to the "faults power" of the AT driver: Injecting "dumb" system-level faults leads to a very degraded environment in which no guarantees can be given.

Some interesting property from https://eprint.iacr.org/2020/1021.pdf: Even in the face of temporary adversarial supremacy, Cardano network can recover after some time

Consensus-focused tests we could start designing & running:
* Basic property we want to ensure is that a node never crashes!
* Genesis:
  * Run cluster of nodes with genesis enabled for a while then at some point stop a node, remove its DB, restart it
  * Have a new node join later
* Utxo-hd enabled (10.4.1)
  * run a mix of nodes with lmdb and in-memory UTxO-HD enabled
  * load the system with transactions
  * There might be new race conditions due to code moving from STM to IO
  * node should restarts gracefully

Our mission should be to try very hard to crash the node, more like stress testing the system
* Just syncing a node from another node in the same container and ensuring they end up on the same chain is interesting

A simple adversarial node we could build:
* Connect to some random node
* Request arbitrary intersection along the node's chain
* Sync a little
* disconnect
* restart

## 2025-04-23

### Antithesis meeting

* Invited people from the Consensus core team joining to discuss one of the interesting bugs found
* Going through the bug found, a Diffusion error about a missing block is detected in the logs
    * precision: previous bugs found by the platform were known, eg. "brown M&Ms"
* randomness is reseeded every 17s, controlled by the platform
* Q: can we see faults injected?
    * not shared by default, fault injectors logs are hard to read
* Q: shrinking fault injections?
    * upcoming feature
* DB is designed to crash if files are deleted
* find interesting points in time from the statistics graph, then poke around in the system at this point
* Q: what's the normal workflow for debugging?
    * some components are hard to debug
* multiverse debugger ~ Jupyter notebook, JS environnement so one can write JS inside
* rate of time in the debug env depends on busyness of the system
* can work on branches from the moment where the bug happened
    * can rewind branches back in time, keeping the same history
    * branching ~ git
* Q: can we replay history against different versions of the software?
    * => want to fuzz ever more
    * use properties as regression tests
* Logs are disabled for consensus
* Trying to query the node for the immmutable tip using cardano-cli inside debugging environment just before the node crashes
    * cardnao-cli cannot access the node.socket, seems like it might be permission issue with reading the socket
    * container does not have sudo/su
    * could use cardano-ping to query the tip from the TCP socket
* sounds like a great tool to debug the problem, need to investigate more -> no disk faults
* could add artifacts, run commands, whatever to the run output
* Next step: reproduce bug with more logs available, possibly using cardano-tracer sidecar, and use multiverse debugger to investigate with consensus team

## 2025-04-16

### Antithesis meeting

* We are able to find the network p2p bug -> the node crashes after 200s
  * 2 bugs in place -> an exception raised + change in exception policy that should only have killed the connection but killed the node
  * why should it take 1 hour to detect? there's an hourly scheduled churn for hosts
  * there are probably different ways of triggering the bug
* working on eventually.sh script -> this might lead to triggering more interesting bugs
  * it's purpose is to causing the chain to diverge
* we are all trying to write more easily properties
* Q: what are the priorities?
  * block fetch bug (Brown M&Ms)? -> this is an old network bug (triggered by CPU load) when node takes too long to demote a peer
  * consensus bug -> we need to wipe the DB and restarting
* There was a bug in the converge.sh script that would rewrite return code to 0
  * we need to change the way we handle SIGTERM -> exit code will be 1
  * There is a property that checks container exit codes, the problem is exit w/ 1 is not distinguishable from any other exit
  * AT could check the SIGTERM in the tester
* Q: what about logs?
  * logs in file make it possible to leverage SDK
  * we are investigating how to write the program for asserting "sometimes it forks" and use shared volume
* AT will write a fault injector that wipes out volume and restart a container
* Also will write a test composer that can spin up a new container
  * delay startup of a node after some time?
  * wrap cardano-node to be able to start/stop/delay?
* AT doesn't have disk faults for now
  * something that's been asked by other people

#### TODO:

* (AB) reach out to core team to test UTxO HD
  * discuss w/ Javier about fault simulation
* (AT) schedule multiverse debugging session
* (AT) start/stop containers wiping out dir
* (KK) block fetch bug
* (JL) write sometimes property using cardano-tracer
* (AT) check SIGTERM exit
* (AT) share docs of all the faults

## 2025-04-13

### Adding cardano-tracer

* One of the issues we had with our initial setup was with logging, as the antithesis platform puts some limits on the amount of log one can output, something which is even checked by a property, currently set at 200MB/core/CPU hour
* The [cardano-tracer](https://github.com/IntersectMBO/cardano-node/blob/master/cardano-tracer) is the new recommended tracing infrastructure for cardano-node that provides a protocol and an agent to forward logs to. This allows logging and tracing across a cluster of nodes to be aggregated  which is something that should prove useful to define properties
* We have added the needed machinery in the [compose](compose) infrastructure:
  1. compile a docker image to run the cardano-tracer executable as it's not available in a pre-compiled form by default
  2. provide tracer configuration to expose prometheus metrics and enable connection from any number of other nodes
  3. modify node's configuration to enable tracing and logging, which was turned off by default
  4. run tracer container as part of compose stack along with cardano-node and "sidecar"
* Some minor roadblocks we hit on this journey:
  * managing users and r/w rights across shared volumes can be tricky. All services are run with a non-privileged user `cardano` but volumes are mounted with owner `root` by default (could not find a way to designate a different user in [compose](https://docs.docker.com/reference/compose-file/volumes/) documentation). We resorted to the usual technique of wrapping up `cardano-tracer` service in a script that modifies owner and rights on the fly upon startup
  * for the cardano-node to forward traces require specific configuration, even though it's enabled by default since 10.2. if `TraceOptions` key is not present, the node won't start
* While a first step would be to just read or follow the logs the cardano-tracer writes to files, the trace-forwarding protocol could be leveraged by write test and properties in a more direct manner, eg. to write a service ingesting logs and traces direclty and using default AT SDK to generate tests

## 2025-04-09

### Meeting summary

* We had our weekly touchpoint with AT team and CF Task Force
* Over the past week we refined our understand of the platform and the CF team is working on a branch with several different setups, including one "large" cluster test where P2P networking can [lead to a crash](https://github.com/IntersectMBO/ouroboros-network/issues/5058) on some particular circumstances
* We discussed our difficulties chasing that particular network bug which requires more runtime than is customary with AT runs
  * We can reproduce the bug using a local docker compose setup so we know it's possible to do it
  * We could not find a way to "miniaturise" the bug, e.g reduce network size, parameters, slot duration, $k$, etc.
* A discussion about the kind of faults we are looking at ensued:
  * network related faults, like the one above, which should be related to handling of adversarial conditions in the system
  * consensus faults which are related to the diffusion logic and chain selection, also depend on resources (eg. selection and diffusiong needs to happen quickly) but mostly related to correct implementation of Ouroboros Praos protocol
  * mempool faults, which are related to diffusion of txs, and can have adversarial effect on the system because of excessive use of resources, race conditions, competing with other parts, etc.
  * ledger faults which relate to the block/transaction evaluation
* AT work should focus (at least for now?) on the first three as ledger is a pure function, although it could be the case an error in the ledger ripples to other layers (eg. diverging computations, unexpected errors, etc.)
  * we note that all layers have an extensive set of property tests
  * it's still unclear how to be best use the tools. AT engine uses different computing characteristics for different workloads/SUTs
  * It's possible to calibrate those performance characteristics in order to better replicate environment but this is not open to customers
* One problem we was the logs output limit. Its purpose is to help reproducing things faster as obviously more output leads to more resources for each run
* While there are certainly bugs that can be triggered through fuzzing I/Os, we need to have a way to run "adversaries" within the system, to inject blocks/transactions to load the system and possibly trigger issues in consensus, mempool, or ledger
  * We don't currently deploy anything like that in our stack, but we should build something
* We discuss how AT does fault injection
  * it's completely rerandomized on purpose, in order to remove human biases as much as possible
  * with more information about baseline guarantees expected from the system, some issues found could be filter out, eg. triggering errors that are beyond the operational limits of the system
  * there's no API to control the various parameters for fault injection

TODOs:

1. extend test execution time to reproduce network bug, and explore how AT analysis can help to understand the bug
1. try to miniaturise the setup to reproduce the bug
2. try to reproduce a consensus bug that requires injection of data
   a. implies we need to build some tool to inject blocks/data in the network
3. defining & refining general security properties
4. integrate [cardano-tracer](https://developers.cardano.org/docs/get-started/cardano-node/new-tracing-system/cardano-tracer/) into compose stack to be able to collect logs
5. express assertion on logs collected with tracer

## 2025-04-02

### Official kick-off meeting

* Antithesis presentation plan:
  * containerize SUT
  * designing tests
  * PBT and what that means, what kind of invariants we can write

* Platform needs:
  * docker images x86_64 archi
  * docker-compose.yaml
  * continuous build pipeline -> push images to AT registry
  * continuous testing
  * implement SSO w/ OIDC (new features, multiverse debugging, private reports)
    * Google workspace w/ SAML?
    * support GitHub auth in the future

* maximize benefits from AT
  * miniaturize setup -> small number of nodes
  * code coverage instrumentation (easy to do in Rust, there's also C instrumentation)
  * use [test composer](https://antithesis.com/docs/test_templates/) to write workload

* antithesis output:
  * webhook endpoint -> trigger the test
  * email -> triage report
  * email -> bug report, statistical tool showing replays/simulations before/after bug point => probability of when in time bugs occur
  * multiverse debugger -> replay tool, allow to run batch command, need to think about debugging workflow (eg. package tools inside images to ease debugging process)
  * reports is available after tests run now, will be available live later on

* no coverage -> default to fuzzing and fault injection, can guide the fuzzer leverage SDK (eg. unreachable)
  * sidecar, more easily instrumente than the actual node

Next steps:

* Credentials to access the platform
* Sharing some documentation and guidelines
* Let's get our first test running :rocket:

## 2025-04-01

### Antithesis Project Pre-kick-off meeting

* Overview of the scope of the project, the deadlines, the goal(s), who's involved, and possible outcomes (see [Antithesis' README](./antithesis/README.md)
* discussed how to get started, what's there, what needs to happen
* Got a demo of some tests the team has already worked on that could be good candidate for onboarding and PoC
* Suggestion: we could use cardano-wallet as a driver to generate transactions?
  * would need to have a way to control several wallets
  * Might be overkill at least at start
