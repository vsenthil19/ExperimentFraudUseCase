# Implementation Plan: Payment Fraud Detection

## Overview

This plan implements a real-time payment fraud detection system as a Java microservice on AWS Lambda. The implementation follows an incremental approach: project scaffolding → data models → validation → individual scorers → decision engine → Lambda orchestration → async event flow → integration testing. All AWS services run on LocalStack for local development.

## Tasks

- [x] 1. Set up project structure, dependencies, and core interfaces
  - [x] 1.1 Create Maven/Gradle project with dependencies
    - Initialize Java 17+ project with build tool configuration
    - Add dependencies: AWS SDK v2 (DynamoDB, EventBridge, Lambda), Jackson for JSON, jqwik for property testing, JUnit 5, Mockito, Testcontainers, LocalStack
    - Configure source directories: `src/main/java`, `src/test/java/property`, `src/test/java/unit`, `src/test/java/integration`
    - _Requirements: 1.1, 5.1_

  - [x] 1.2 Define core data model records and enums
    - Create `FasterPaymentRequest`, `BankAccount`, `ConfirmationOfPayee`, `Channel`, `GeoLocation`, `ChannelType`, `CopResult` records/enums
    - Create `CustomerProfile`, `BeneficiaryStatus`, `BeneficiaryFlag` records/enums
    - Create `RiskAssessment`, `FraudDecision`, `FraudDecisionResponse`, `RiskBreakdown`, `RiskFactor`, `Decision` records/enums
    - Create `ValidationResult`, `ValidationError` records
    - Create `StepUpAction`, `StepUpType` records/enums
    - Create `ScorerResult` record and `ComponentScorer` interface
    - Configure Jackson serialization annotations for enum string names and null handling
    - _Requirements: 1.2, 1.6, 10.1, 10.5, 10.6_

  - [x] 1.3 Define repository interfaces
    - Create `CustomerProfileRepository` interface with `getProfile` and `updateProfile` methods
    - Create `BeneficiaryRegistryRepository` interface with `getStatus` method
    - Create `EventPublisher` interface with `publishDecisionMade` method
    - _Requirements: 3.3, 4.1, 6.1_

- [x] 2. Implement request validation
  - [x] 2.1 Implement RequestValidator
    - Validate account number format (exactly 8 numeric digits) for both debtor and creditor
    - Validate sort code format (exactly 6 numeric digits) for both debtor and creditor
    - Validate amount range [0.01, 1000000.00]
    - Validate currency equals GBP
    - Validate paymentReference ≤ 18 characters
    - Validate channel type is one of MOBILE, ONLINE_BANKING, API, BRANCH, PHONE
    - Validate CoP result is one of MATCH, CLOSE_MATCH, NO_MATCH, NOT_AVAILABLE (if present)
    - Validate required fields are present (debtorAccount, creditorAccount, amount, currency, channel)
    - Aggregate all validation errors into a single response
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12_

  - [ ]* 2.2 Write property test for validation rejects invalid requests
    - **Property 11: Validation Rejects Invalid Requests**
    - Generate random FasterPaymentRequests with at least one invalid field
    - Assert RequestValidator rejects every generated invalid request and identifies the invalid field(s)
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10**

  - [ ]* 2.3 Write property test for valid requests pass validation
    - **Property 12: Valid Requests Pass Validation**
    - Generate random FasterPaymentRequests where all fields conform to the schema
    - Assert RequestValidator accepts every generated valid request
    - **Validates: Requirements 7.11**

  - [ ]* 2.4 Write property test for multiple validation errors reported together
    - **Property 13: Multiple Validation Errors Reported Together**
    - Generate FasterPaymentRequests with N > 1 invalid fields
    - Assert the validation response contains exactly N error entries
    - **Validates: Requirements 7.12**

- [x] 3. Implement component scorers
  - [x] 3.1 Implement AmountScorer
    - Calculate score based on deviation from historical mean using stddev
    - Apply formula: min(25, 10 × floor((amount - mean) / stddev)) when amount > mean + 3σ
    - Apply default threshold of £500 when debtor has < 5 transactions in 90 days
    - Return ScorerResult with score [0, 25] and explanation
    - _Requirements: 3.1, 3.4_

  - [ ]* 3.2 Write property test for amount score calculation
    - **Property 5: Amount Score Calculation**
    - Generate random (amount, mean, stddev) tuples where amount > mean + 3σ
    - Assert amountScore increase equals min(50, 10 × floor((amount - mean) / stddev)), capped at 25
    - **Validates: Requirements 3.1**

  - [ ]* 3.3 Write property test for low-history default threshold
    - **Property 6: Low-History Default Threshold**
    - Generate profiles with 0-4 transactions in 90 days
    - Assert dynamic threshold applied is £500
    - **Validates: Requirements 3.4**

  - [x] 3.4 Implement CopScorer
    - Map CoP MATCH → 0, CLOSE_MATCH → [5, 15], NO_MATCH → [20, 25], NOT_AVAILABLE → [10, 20], null/absent → 15
    - Return ScorerResult with score [0, 25] and explanation
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

  - [ ]* 3.5 Write property test for CoP score range mapping
    - **Property 14: CoP Score Range Mapping**
    - Generate random CoP results (MATCH, CLOSE_MATCH, NO_MATCH, NOT_AVAILABLE, null)
    - Assert copScore falls within the specified range for each CoP result
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5**

  - [x] 3.6 Implement ChannelScorer
    - Add ≥10 points for unknown device (deviceId not in known devices)
    - Add ≥15 points for geolocation > 50 km from all known locations
    - Add ≥5 points for PHONE channel type
    - Apply unknown device and location increases for accounts with no stored history
    - Cap total at 25; return ScorerResult with explanation
    - _Requirements: 9.1, 9.2, 9.3, 9.5_

  - [ ]* 3.7 Write property test for channel score risk factors
    - **Property 15: Channel Score Risk Factors**
    - Generate random devices, locations, and channels against customer profiles
    - Assert channelScore includes correct minimum points for each risk factor
    - **Validates: Requirements 9.1, 9.2, 9.3, 9.5**

  - [x] 3.8 Implement BehaviouralScorer
    - Add ≥10 points when session duration < 50% of debtor's historical average
    - Return ScorerResult with score [0, 25] and explanation
    - _Requirements: 9.4_

  - [ ]* 3.9 Write property test for behavioural score short session
    - **Property 16: Behavioural Score Short Session**
    - Generate requests with session duration < 50% of average
    - Assert behaviouralScore is at least 10
    - **Validates: Requirements 9.4**

- [x] 4. Checkpoint - Ensure all scorer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement RiskScoringEngine and DecisionEngine
  - [x] 5.1 Implement RiskScoringEngine
    - Compose AmountScorer, CopScorer, BehaviouralScorer, and ChannelScorer
    - Sum all four component scores into composite riskScore
    - Collect risk factors from each scorer into RiskAssessment
    - _Requirements: 1.2, 1.6_

  - [ ]* 5.2 Write property test for risk score composition invariant
    - **Property 1: Risk Score Composition Invariant**
    - Generate random valid requests and profiles
    - Assert riskScore equals amountScore + copScore + behaviouralScore + channelScore
    - Assert each component score is in [0, 25]
    - **Validates: Requirements 1.2**

  - [ ]* 5.3 Write property test for risk score bounds invariant
    - **Property 2: Risk Score Bounds Invariant**
    - Generate random valid requests
    - Assert riskScore is in [0, 100]
    - **Validates: Requirements 1.6**

  - [x] 5.4 Implement DecisionEngine
    - Map riskScore [0, 30] → ALLOW, [31, 70] → REVIEW, [71, 100] → BLOCK
    - Apply beneficiary override: HIGH_RISK → minimum score 71
    - Apply beneficiary override: MULE_LINKED → always BLOCK
    - Apply dynamic threshold override: amount > mean + 3σ → minimum REVIEW
    - Include up to 3 top risk factors in decision
    - _Requirements: 1.3, 1.4, 1.5, 4.1, 4.2, 3.2, 2.5_

  - [ ]* 5.5 Write property test for score-to-decision mapping
    - **Property 3: Score-to-Decision Mapping**
    - Generate random riskScores in [0, 100] with no overrides
    - Assert correct ALLOW/REVIEW/BLOCK mapping at boundaries
    - **Validates: Requirements 1.3, 1.4, 1.5**

  - [ ]* 5.6 Write property test for dynamic threshold override
    - **Property 4: Dynamic Threshold Override**
    - Generate requests with amount > mean + 3σ
    - Assert decision is at least REVIEW regardless of computed riskScore
    - **Validates: Requirements 3.2**

  - [ ]* 5.7 Write property test for high-risk beneficiary minimum score
    - **Property 7: High-Risk Beneficiary Minimum Score**
    - Generate requests directed to HIGH_RISK flagged accounts
    - Assert final riskScore is at least 71
    - **Validates: Requirements 4.1**

  - [ ]* 5.8 Write property test for mule-linked beneficiary block
    - **Property 8: Mule-Linked Beneficiary Block**
    - Generate requests directed to MULE_LINKED flagged accounts
    - Assert decision is always BLOCK
    - **Validates: Requirements 4.2**

  - [ ]* 5.9 Write property test for step-up risk factor limit
    - **Property 9: Step-Up Risk Factor Limit**
    - Generate decisions that trigger step-up actions with 1-10 risk factors
    - Assert step-up action includes at most 3 risk factors
    - **Validates: Requirements 2.5**

- [x] 6. Checkpoint - Ensure all scoring and decision tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement timeout circuit breaker and concurrency guard
  - [x] 7.1 Implement TimeoutCircuitBreaker
    - Set 280ms scoring timeout with CompletableFuture
    - Return REVIEW with timeout risk factor on TimeoutException
    - Return REVIEW with error risk factor on other exceptions
    - Reserve 20ms for response serialization
    - _Requirements: 5.2, 1.7_

  - [x] 7.2 Implement ConcurrencyGuard
    - Use Semaphore with 500 permits
    - Return capacity exceeded error when permits exhausted
    - Ensure permit release in finally block
    - _Requirements: 5.3, 5.4_

  - [ ]* 7.3 Write unit tests for TimeoutCircuitBreaker
    - Test scoring timeout triggers REVIEW with reason
    - Test internal error triggers REVIEW with reason
    - Test successful execution within budget
    - _Requirements: 1.7, 5.2_

  - [ ]* 7.4 Write unit tests for ConcurrencyGuard
    - Test >500 concurrent requests produce rejection error
    - Test permit release on completion
    - _Requirements: 5.3, 5.4_

- [x] 8. Implement DynamoDB repository layer
  - [x] 8.1 Implement DynamoDB single-table schema and configuration
    - Define table with PK/SK structure for CustomerProfile, BeneficiaryRegistry, TransactionHistory, PaidBeneficiary, DecisionAudit entities
    - Configure GSI (DecisionByDate) for querying decisions by type and date range
    - Configure AWS SDK v2 DynamoDB Enhanced Client with table schema
    - _Requirements: 3.3, 4.3, 6.4_

  - [x] 8.2 Implement CustomerProfileRepository (DynamoDB)
    - Implement `getProfile` with PK=`CUST#{sortCode}#{accountNumber}`, SK=`PROFILE`
    - Implement `updateProfile` for profile attribute updates
    - Use BatchGetItem for efficient reads
    - _Requirements: 3.3, 9.5_

  - [x] 8.3 Implement BeneficiaryRegistryRepository (DynamoDB)
    - Implement `getStatus` with PK=`BENE#{sortCode}#{accountNumber}`, SK=`STATUS`
    - Return BeneficiaryStatus with flag and lastUpdated
    - _Requirements: 4.1, 4.2, 4.3_

- [x] 9. Implement EventBridge publishing and audit logging
  - [x] 9.1 Implement EventPublisher (EventBridge)
    - Publish `DecisionMade` events to EventBridge with fire-and-forget semantics
    - Serialize DecisionEvent to JSON with all required fields
    - Handle publish failures gracefully (log locally, don't block response)
    - _Requirements: 6.1, 6.5_

  - [x] 9.2 Implement AuditLog Lambda handler
    - Consume `DecisionMade` events from EventBridge
    - Persist decision records to DynamoDB (DecisionAudit entity)
    - Archive decision records to S3 for long-term storage
    - Implement retry logic (up to 3 retries with exponential backoff)
    - _Requirements: 6.1, 6.2, 6.3, 6.5, 6.6_

  - [ ]* 9.3 Write property test for audit record well-formedness
    - **Property 10: Audit Record Well-Formedness**
    - Generate random fraud decisions
    - Assert persisted audit record contains messageId, timestamp, riskScore, decision, and all four component scores
    - Assert each risk factor explanation is ≤ 200 characters
    - **Validates: Requirements 6.1, 6.2**

- [x] 10. Implement JSON serialization configuration
  - [x] 10.1 Configure Jackson ObjectMapper for FasterPaymentRequest and FraudDecisionResponse
    - Configure enum serialization as string names
    - Configure null optional field handling (preserve nulls, don't substitute defaults)
    - Configure BigDecimal amount to 2 decimal places
    - Configure Instant serialization/deserialization
    - _Requirements: 10.1, 10.2, 10.5, 10.6_

  - [ ]* 10.2 Write property test for FasterPaymentRequest serialization round-trip
    - **Property 17: FasterPaymentRequest Serialization Round-Trip**
    - Generate random valid FasterPaymentRequest objects (including null optional fields)
    - Assert serialize → deserialize produces value-equal object
    - **Validates: Requirements 10.1, 10.2, 10.3, 10.5, 10.6**

  - [ ]* 10.3 Write property test for FraudDecisionResponse serialization round-trip
    - **Property 18: FraudDecisionResponse Serialization Round-Trip**
    - Generate random valid FraudDecisionResponse objects
    - Assert serialize → deserialize produces value-equal object
    - **Validates: Requirements 10.4**

- [x] 11. Implement FraudDetectionHandler (Lambda orchestration)
  - [x] 11.1 Implement FraudDetectionHandler
    - Deserialize APIGatewayProxyRequestEvent to FasterPaymentRequest
    - Invoke RequestValidator; return HTTP 400 with all errors on failure
    - Acquire ConcurrencyGuard permit; return capacity error if unavailable
    - Read CustomerProfile and BeneficiaryStatus via repositories (BatchGetItem)
    - Invoke RiskScoringEngine within TimeoutCircuitBreaker
    - Invoke DecisionEngine with assessment, beneficiary status, profile, request
    - Publish DecisionMade event via EventPublisher (fire-and-forget)
    - Serialize FraudDecisionResponse and return HTTP 200
    - Release ConcurrencyGuard permit in finally block
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.7, 1.8, 5.1, 5.2, 5.3, 5.4_

- [x] 12. Implement ProfileUpdate Lambda
  - [x] 12.1 Implement ProfileUpdate Lambda handler
    - Consume `TransactionCompleted` events from EventBridge
    - Recalculate behavioural statistics (mean, stddev, device list, session averages)
    - Update CustomerProfile in DynamoDB via repository
    - _Requirements: 3.3, 9.4, 9.5_

- [x] 13. Checkpoint - Ensure all unit and property tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Integration testing with LocalStack
  - [x] 14.1 Write integration tests for end-to-end fraud detection flow
    - Set up LocalStack with Testcontainers (DynamoDB, EventBridge, Lambda, S3, API Gateway)
    - Test full request → validation → scoring → decision → event publish flow
    - Verify DynamoDB reads return correct customer profiles and beneficiary flags
    - Verify EventBridge receives DecisionMade events
    - Test latency is within 300ms SLA for the synchronous path
    - _Requirements: 1.1, 5.1, 4.3, 6.6_

  - [x] 14.2 Write integration tests for audit log flow
    - Test DecisionMade event → AuditLog Lambda → DynamoDB persistence
    - Test S3 archival of decision records
    - Test retry logic on DynamoDB write failure
    - Test query by messageId, debtor account, and date range returns within 5 seconds
    - _Requirements: 6.1, 6.3, 6.4, 6.5_

  - [x] 14.3 Write integration tests for beneficiary flag propagation
    - Test updating beneficiary flag → subsequent payment evaluations use new flag within 5 seconds
    - _Requirements: 4.3_

- [~] 15. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties using jqwik with minimum 100 iterations
- Unit tests validate specific examples and edge cases
- Integration tests use LocalStack via Testcontainers for full AWS service emulation
- The design constrains CoP NO_MATCH to [20, 25] in the component scorer (capped at 25), which is compatible with Requirement 8.3's [20, 35] range
- All scorers return values in [0, 25] per the ComponentScorer interface contract

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["2.1", "3.1", "3.4", "3.6", "3.8"] },
    { "id": 3, "tasks": ["2.2", "2.3", "2.4", "3.2", "3.3", "3.5", "3.7", "3.9"] },
    { "id": 4, "tasks": ["5.1", "5.4", "10.1"] },
    { "id": 5, "tasks": ["5.2", "5.3", "5.5", "5.6", "5.7", "5.8", "5.9", "10.2", "10.3"] },
    { "id": 6, "tasks": ["7.1", "7.2", "8.1"] },
    { "id": 7, "tasks": ["7.3", "7.4", "8.2", "8.3"] },
    { "id": 8, "tasks": ["9.1", "9.2"] },
    { "id": 9, "tasks": ["9.3", "11.1", "12.1"] },
    { "id": 10, "tasks": ["14.1", "14.2", "14.3"] }
  ]
}
```
