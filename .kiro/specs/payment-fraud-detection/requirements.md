# Requirements Document

## Introduction

This document defines the requirements for a real-time payment fraud detection system targeting Authorised Push Payment (APP) scams. The system operates as a Java microservice that intercepts payment requests, applies risk scoring using behavioural, device, and beneficiary intelligence, and returns a fraud decision (ALLOW, REVIEW, or BLOCK) within a sub-300ms SLA. The system must comply with FCA regulatory expectations and provide full decision explainability for audit purposes.

## Glossary

- **Fraud_Detection_Engine**: The core service responsible for receiving payment requests, computing risk scores, and returning fraud decisions in real time.
- **Risk_Scorer**: The component that calculates a composite risk score from amount, Confirmation of Payee (CoP), behavioural, and channel factors.
- **Beneficiary_Registry**: The data store containing beneficiary risk profiles, including mule-linked and high-risk flags.
- **Step_Up_Authenticator**: The component responsible for triggering additional authentication challenges or scam-specific warnings when a payment is identified as high-risk.
- **Decision_Logger**: The component responsible for persisting all fraud decisions with explainability metadata for audit and regulatory compliance.
- **FasterPaymentRequest**: The incoming payment message schema containing debtor/creditor accounts, amount, channel information, and CoP results.
- **Risk_Score**: A numeric value between 0 and 100 representing the fraud likelihood of a payment, computed as: amountScore + copScore + behaviouralScore + channelScore.
- **Confirmation_of_Payee (CoP)**: A name-checking service result indicating whether the creditor name matches the account holder (MATCH, CLOSE_MATCH, NO_MATCH, NOT_AVAILABLE).
- **Channel**: The medium through which a payment is initiated (MOBILE, ONLINE_BANKING, API, BRANCH, PHONE).
- **SLA**: Service Level Agreement; the maximum acceptable response time for a fraud decision (300 milliseconds).
- **APP_Scam**: Authorised Push Payment scam where a customer is socially engineered into making a payment to a fraudster.
- **Mule_Account**: A bank account used by criminals to receive and launder proceeds of fraud.
- **Strong_Customer_Authentication (SCA)**: A regulatory requirement for multi-factor authentication during payment initiation.

## Requirements

### Requirement 1: Real-Time Risk Scoring for New Beneficiary Payments

**User Story:** As a fraud operations analyst, I want the system to perform real-time risk scoring when a customer pays a new beneficiary, so that potential APP scams are intercepted before funds are transferred.

#### Acceptance Criteria

1. WHEN a FasterPaymentRequest is received with a creditor account not previously paid by the debtor, THE Fraud_Detection_Engine SHALL compute a Risk_Score using behavioural, device, and beneficiary intelligence and return a decision within 300 milliseconds measured from request receipt to response dispatch.
2. WHEN a FasterPaymentRequest is received with a creditor account not previously paid by the debtor, THE Risk_Scorer SHALL calculate the Risk_Score as the sum of amountScore, copScore, behaviouralScore, and channelScore, where each component produces a value between 0 and 25 (inclusive).
3. WHEN the Risk_Score is between 0 and 30 (inclusive), THE Fraud_Detection_Engine SHALL return a decision of ALLOW together with the computed Risk_Score.
4. WHEN the Risk_Score is between 31 and 70 (inclusive), THE Fraud_Detection_Engine SHALL return a decision of REVIEW together with the computed Risk_Score.
5. WHEN the Risk_Score is between 71 and 100 (inclusive), THE Fraud_Detection_Engine SHALL return a decision of BLOCK together with the computed Risk_Score.
6. THE Risk_Scorer SHALL produce a Risk_Score value between 0 and 100 (inclusive) for all valid FasterPaymentRequest inputs.
7. IF the Fraud_Detection_Engine fails to compute a Risk_Score within 300 milliseconds or encounters an internal error during scoring, THEN THE Fraud_Detection_Engine SHALL return a decision of REVIEW and log the failure reason.
8. IF a FasterPaymentRequest is received with missing or malformed mandatory fields, THEN THE Fraud_Detection_Engine SHALL reject the request with an error response indicating the validation failure, without producing a Risk_Score.

### Requirement 2: Step-Up Authentication for High-Risk Payments

**User Story:** As a customer, I want to receive a targeted warning or authentication challenge when my payment is flagged as high-risk, so that I am protected from social engineering scams.

#### Acceptance Criteria

1. WHEN the Fraud_Detection_Engine returns a decision of REVIEW, THE Step_Up_Authenticator SHALL present the customer with a warning message specific to the identified scam typology (e.g., APP scam, investment fraud, romance fraud) within 2 seconds of receiving the decision.
2. WHEN the customer acknowledges a REVIEW warning, THE Step_Up_Authenticator SHALL allow the payment to proceed.
3. WHEN the Fraud_Detection_Engine returns a decision of BLOCK, THE Step_Up_Authenticator SHALL trigger a Strong_Customer_Authentication challenge and prevent the payment from proceeding until the challenge is successfully completed.
4. IF the customer fails the Strong_Customer_Authentication challenge 3 consecutive times or does not complete it within 5 minutes, THEN THE Step_Up_Authenticator SHALL reject the payment and notify the customer that the payment has been blocked.
5. WHEN the Step_Up_Authenticator triggers a warning or challenge, THE Step_Up_Authenticator SHALL include up to 3 risk factors that contributed to the decision, each describing an observable transaction attribute (e.g., unusual payee, amount exceeds typical pattern, new device detected).

### Requirement 3: Dynamic Threshold Verification

**User Story:** As a fraud operations analyst, I want payments exceeding dynamic thresholds based on customer profile to require additional verification, so that unusual payment patterns are challenged.

#### Acceptance Criteria

1. WHEN a FasterPaymentRequest amount exceeds the debtor's historical average transaction amount by more than 3 standard deviations, THE Fraud_Detection_Engine SHALL increase the amountScore by the lesser of 50 points or 10 points per standard deviation above the mean.
2. WHEN a FasterPaymentRequest amount exceeds the debtor's dynamic threshold (defined as the historical mean transaction amount plus 3 standard deviations calculated over the most recent 90 days), THE Fraud_Detection_Engine SHALL override the fraud decision to a minimum of REVIEW regardless of the overall Risk_Score.
3. WHEN a FasterPaymentRequest is received, THE Fraud_Detection_Engine SHALL calculate the debtor's dynamic threshold using transaction history from the most recent 90 days, completing the calculation within the 300-millisecond SLA.
4. IF the debtor has fewer than 5 transactions in the most recent 90 days, THEN THE Fraud_Detection_Engine SHALL apply a default dynamic threshold of £500 until sufficient transaction history is available.

### Requirement 4: Beneficiary Risk Restrictions

**User Story:** As a fraud operations analyst, I want the system to restrict or delay payments to flagged beneficiaries, so that funds are not transferred to known mule accounts.

#### Acceptance Criteria

1. WHILE a creditor account is flagged as high-risk in the Beneficiary_Registry, THE Fraud_Detection_Engine SHALL apply a minimum Risk_Score of 71 to payments directed to that account.
2. WHILE a creditor account is flagged as mule-linked in the Beneficiary_Registry, THE Fraud_Detection_Engine SHALL return a decision of BLOCK for all payments directed to that account.
3. WHEN the Beneficiary_Registry flag for a creditor account is updated, THE Fraud_Detection_Engine SHALL apply the updated flag to all subsequent payment evaluations within 5 seconds.

### Requirement 5: Sub-Second Decision SLA

**User Story:** As a product owner, I want the fraud detection system to return decisions within 300 milliseconds, so that customer experience is not degraded during payment flows.

#### Acceptance Criteria

1. THE Fraud_Detection_Engine SHALL return a fraud decision (ALLOW, REVIEW, or BLOCK) within 300 milliseconds of receiving a valid FasterPaymentRequest for at least 99% of requests measured over any 1-minute window.
2. IF the Fraud_Detection_Engine cannot complete risk scoring within 280 milliseconds, THEN THE Fraud_Detection_Engine SHALL return a decision of REVIEW with a risk factor indicating timeout within the remaining 20 milliseconds, ensuring total response time does not exceed 300 milliseconds.
3. WHILE processing up to 500 concurrent FasterPaymentRequest evaluations, THE Fraud_Detection_Engine SHALL maintain the 300-millisecond response time for at least 99% of requests.
4. IF the number of concurrent FasterPaymentRequest evaluations exceeds 500, THEN THE Fraud_Detection_Engine SHALL reject additional requests with an error indicating capacity exceeded rather than silently degrading response times.

### Requirement 6: Decision Audit Logging with Explainability

**User Story:** As a compliance officer, I want all fraud decisions logged with explainability metadata, so that the organisation meets FCA regulatory expectations and can demonstrate decision rationale.

#### Acceptance Criteria

1. WHEN the Fraud_Detection_Engine returns a fraud decision, THE Decision_Logger SHALL persist the decision record including: messageId, timestamp, Risk_Score, decision, and contributing risk factors (amountScore, copScore, behaviouralScore, channelScore).
2. WHEN the Fraud_Detection_Engine returns a fraud decision, THE Decision_Logger SHALL include for each contributing risk factor a natural language explanation of no more than 200 characters that states the input condition evaluated and its numeric contribution to the Risk_Score.
3. THE Decision_Logger SHALL retain all decision records for a minimum of 7 years in compliance with FCA record-keeping requirements, and SHALL prevent modification or deletion of persisted decision records.
4. THE Decision_Logger SHALL return query results matching by messageId, debtor account, creditor account, decision type, or date range (up to 7 years) within 5 seconds.
5. IF the Decision_Logger fails to persist a decision record, THEN THE Decision_Logger SHALL retry persistence up to 3 times and SHALL not block or delay the Fraud_Detection_Engine response to the payment request.
6. WHEN the Fraud_Detection_Engine returns a fraud decision, THE Decision_Logger SHALL persist the decision record within 5 seconds of the decision being made.

### Requirement 7: Payment Request Validation

**User Story:** As a system integrator, I want the system to validate incoming payment requests against the defined schema, so that malformed requests are rejected before processing.

#### Acceptance Criteria

1. WHEN a FasterPaymentRequest is received with an invalid debtorAccount accountNumber (not exactly 8 numeric digits), THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
2. WHEN a FasterPaymentRequest is received with an invalid debtorAccount sortCode (not exactly 6 numeric digits), THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
3. WHEN a FasterPaymentRequest is received with an invalid creditorAccount accountNumber (not exactly 8 numeric digits), THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
4. WHEN a FasterPaymentRequest is received with an invalid creditorAccount sortCode (not exactly 6 numeric digits), THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
5. WHEN a FasterPaymentRequest is received with an amount less than 0.01 or greater than 1000000.00, THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
6. WHEN a FasterPaymentRequest is received with a currency other than GBP, THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
7. WHEN a FasterPaymentRequest is received with a paymentReference exceeding 18 characters, THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
8. WHEN a FasterPaymentRequest is received with a channel type not in (MOBILE, ONLINE_BANKING, API, BRANCH, PHONE), THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
9. WHEN a FasterPaymentRequest is received with a confirmationOfPayee result not in (MATCH, CLOSE_MATCH, NO_MATCH, NOT_AVAILABLE), THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which field failed validation.
10. WHEN a FasterPaymentRequest is received with any required field missing (debtorAccount, creditorAccount, amount, currency, or channel), THE Fraud_Detection_Engine SHALL reject the request with an HTTP 400 response containing an error message indicating which required field is absent.
11. WHEN a FasterPaymentRequest is received and all fields pass validation, THE Fraud_Detection_Engine SHALL accept the request and proceed to risk scoring within 100 milliseconds of receipt.
12. IF a FasterPaymentRequest contains multiple validation errors, THEN THE Fraud_Detection_Engine SHALL return all detected validation errors in a single HTTP 400 response rather than reporting only the first error encountered.

### Requirement 8: Confirmation of Payee Risk Assessment

**User Story:** As a fraud operations analyst, I want CoP results to influence the risk score, so that payments where the beneficiary name does not match receive higher scrutiny.

#### Acceptance Criteria

1. WHEN a FasterPaymentRequest has a confirmationOfPayee result of MATCH, THE Risk_Scorer SHALL assign a copScore of 0.
2. WHEN a FasterPaymentRequest has a confirmationOfPayee result of CLOSE_MATCH, THE Risk_Scorer SHALL assign an integer copScore between 5 and 15 (inclusive).
3. WHEN a FasterPaymentRequest has a confirmationOfPayee result of NO_MATCH, THE Risk_Scorer SHALL assign an integer copScore between 20 and 35 (inclusive).
4. WHEN a FasterPaymentRequest has a confirmationOfPayee result of NOT_AVAILABLE, THE Risk_Scorer SHALL assign an integer copScore between 10 and 20 (inclusive).
5. IF a FasterPaymentRequest does not contain a confirmationOfPayee field or the field is null, THEN THE Risk_Scorer SHALL assign a copScore of 15 indicating elevated uncertainty.

### Requirement 9: Channel and Device Risk Assessment

**User Story:** As a fraud operations analyst, I want channel and device information to influence the risk score, so that payments from unusual devices or channels receive higher scrutiny.

#### Acceptance Criteria

1. WHEN a FasterPaymentRequest originates from a deviceId not present in the debtor account's stored device history, THE Risk_Scorer SHALL increase the channelScore by a minimum of 10 points.
2. WHEN a FasterPaymentRequest originates from a geoLocation more than 50 km from all previously recorded locations for the debtor account, THE Risk_Scorer SHALL increase the channelScore by a minimum of 15 points.
3. WHEN a FasterPaymentRequest is initiated via the PHONE channel, THE Risk_Scorer SHALL increase the channelScore by a minimum of 5 points due to elevated social engineering risk.
4. WHEN a FasterPaymentRequest session duration is less than 50% of the debtor's historical average session duration, THE Risk_Scorer SHALL increase the behaviouralScore by a minimum of 10 points.
5. IF the debtor account has no stored device history, location history, or session history at the time of assessment, THEN THE Risk_Scorer SHALL treat the request as if it originates from an unrecognised device and location, applying the channelScore increases defined in criteria 1 and 2.

### Requirement 10: Risk Score Serialization Round-Trip

**User Story:** As a system integrator, I want risk assessment data to be accurately serialized and deserialized between service boundaries, so that no scoring information is lost during inter-service communication.

#### Acceptance Criteria

1. THE Fraud_Detection_Engine SHALL serialize FasterPaymentRequest objects to JSON format for inter-service communication.
2. THE Fraud_Detection_Engine SHALL deserialize JSON payloads back into FasterPaymentRequest objects preserving all field values, including the amount field to 2 decimal places and the Risk_Score as an integer between 0 and 100.
3. THE Fraud_Detection_Engine SHALL ensure that for all valid FasterPaymentRequest objects, serializing to JSON then deserializing back produces an object where every field (including nested objects debtorAccount, creditorAccount, confirmationOfPayee, riskAssessment, and channel with geoLocation) is equal by value to the corresponding field in the original object.
4. THE Fraud_Detection_Engine SHALL ensure that for all valid risk assessment responses, serializing to JSON then deserializing back produces an object where every field (including decision, Risk_Score, and contributing risk factors) is equal by value to the corresponding field in the original object.
5. THE Fraud_Detection_Engine SHALL serialize enum fields (channel type, confirmationOfPayee result, and decision) as their string name representation and deserialize them back to the corresponding enum value.
6. IF a FasterPaymentRequest contains null or absent optional fields (such as geoLocation or paymentReference), THEN THE Fraud_Detection_Engine SHALL preserve those fields as null after a serialization-deserialization round-trip rather than substituting default values.
