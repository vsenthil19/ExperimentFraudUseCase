# Requirements Document

## Introduction

This feature provides a web-based user interface for submitting UK Faster Payment requests to the existing fraud detection service. The UI allows users to enter payment details, submit them for fraud screening, and view the resulting decision. When the fraud service returns a REVIEW decision, the UI displays the risk factors that triggered the hold and offers the user an option to confirm and proceed with the payment. When the service returns a BLOCK decision, the UI displays the reasons and informs the user the payment cannot proceed.

## Glossary

- **Payment_Form**: The web form component where users enter Faster Payment details including debtor account, creditor account, amount, payment reference, channel, and Confirmation of Payee information.
- **Fraud_Detection_API**: The existing AWS Lambda-backed API Gateway endpoint that accepts a FasterPaymentRequest and returns a FraudDecisionResponse containing a decision (ALLOW, REVIEW, or BLOCK), risk score, risk breakdown, and risk factors.
- **Result_Display**: The UI component that presents the fraud decision outcome to the user after submission.
- **Sort_Code**: A six-digit numerical code identifying a UK bank branch (format: NN-NN-NN).
- **Account_Number**: An eight-digit numerical code identifying an individual bank account.
- **CoP_Result**: The outcome of a Confirmation of Payee check, one of: MATCH, CLOSE_MATCH, NO_MATCH, or NOT_AVAILABLE.
- **Channel_Type**: The channel through which the payment is initiated, one of: MOBILE, ONLINE_BANKING, API, BRANCH, or PHONE.
- **Risk_Factor**: A category and explanation pair describing why a payment was flagged during fraud screening.
- **Confirm_Payment_Action**: The user action to override a REVIEW decision and proceed with the payment.

## Requirements

### Requirement 1: Payment Form Display

**User Story:** As a payment operator, I want to see a form with all required payment fields, so that I can enter Faster Payment details for fraud screening.

#### Acceptance Criteria

1. THE Payment_Form SHALL display input fields for debtor Sort_Code, debtor Account_Number, and debtor account name (maximum 70 characters).
2. THE Payment_Form SHALL display input fields for creditor Sort_Code, creditor Account_Number, and creditor account name (maximum 70 characters).
3. THE Payment_Form SHALL display an input field for the payment amount in GBP that accepts numeric values with up to 2 decimal places within the range 0.01 to 999,999,999.99.
4. THE Payment_Form SHALL display an input field for the payment reference with a maximum length of 35 characters.
5. THE Payment_Form SHALL display a dropdown selection for Channel_Type with options: MOBILE, ONLINE_BANKING, API, BRANCH, and PHONE.
6. THE Payment_Form SHALL display a dropdown selection for CoP_Result with options: MATCH, CLOSE_MATCH, NO_MATCH, and NOT_AVAILABLE.
7. THE Payment_Form SHALL display an input field for the CoP matched name with a maximum length of 70 characters.
8. THE Payment_Form SHALL display a submit button labelled "Check Payment".
9. WHEN the Payment_Form is first loaded, THE Payment_Form SHALL display all input fields in an empty state and all dropdown selections with no option pre-selected.

### Requirement 2: Input Validation

**User Story:** As a payment operator, I want the form to validate my input before submission, so that I avoid sending malformed requests to the fraud detection service.

#### Acceptance Criteria

1. WHEN the user submits the Payment_Form with an empty debtor Sort_Code, THEN THE Payment_Form SHALL display a validation error message "Debtor sort code is required".
2. WHEN the user submits the Payment_Form with a debtor Sort_Code that does not match the format NN-NN-NN (six digits), THEN THE Payment_Form SHALL display a validation error message "Debtor sort code must be 6 digits".
3. WHEN the user submits the Payment_Form with an empty debtor Account_Number, THEN THE Payment_Form SHALL display a validation error message "Debtor account number is required".
4. WHEN the user submits the Payment_Form with a debtor Account_Number that is not exactly 8 digits, THEN THE Payment_Form SHALL display a validation error message "Debtor account number must be 8 digits".
5. WHEN the user submits the Payment_Form with an empty creditor Sort_Code, THEN THE Payment_Form SHALL display a validation error message "Creditor sort code is required".
6. WHEN the user submits the Payment_Form with a creditor Sort_Code that does not match the format NN-NN-NN (six digits), THEN THE Payment_Form SHALL display a validation error message "Creditor sort code must be 6 digits".
7. WHEN the user submits the Payment_Form with an empty creditor Account_Number, THEN THE Payment_Form SHALL display a validation error message "Creditor account number is required".
8. WHEN the user submits the Payment_Form with a creditor Account_Number that is not exactly 8 digits, THEN THE Payment_Form SHALL display a validation error message "Creditor account number must be 8 digits".
9. WHEN the user submits the Payment_Form with an amount that is not a valid number, less than or equal to zero, or greater than 999999999.99, THEN THE Payment_Form SHALL display a validation error message "Amount must be a number between 0.01 and 999,999,999.99".
10. WHEN the user submits the Payment_Form with an amount that has more than 2 decimal places, THEN THE Payment_Form SHALL display a validation error message "Amount must have at most 2 decimal places".
11. WHEN the user submits the Payment_Form with an empty amount field, THEN THE Payment_Form SHALL display a validation error message "Amount is required".
12. WHEN the user submits the Payment_Form without selecting a Channel_Type, THEN THE Payment_Form SHALL display a validation error message "Channel type is required".
13. IF one or more validation errors exist, THEN THE Payment_Form SHALL display all applicable validation error messages simultaneously and SHALL NOT send a request to the Fraud_Detection_API.
14. WHEN the user submits the Payment_Form and all fields pass validation, THE Payment_Form SHALL clear any previously displayed validation error messages.

### Requirement 3: Payment Submission

**User Story:** As a payment operator, I want to submit a payment for fraud screening, so that I can determine whether the payment is safe to process.

#### Acceptance Criteria

1. WHEN the user submits a valid Payment_Form, THE Payment_Form SHALL send a POST request to the Fraud_Detection_API with the payment details formatted as a FasterPaymentRequest JSON payload, including a system-generated messageId and timestamp.
2. WHILE the Fraud_Detection_API request is in progress, THE Payment_Form SHALL display a loading indicator and disable the submit button.
3. WHEN the Fraud_Detection_API returns a successful response, THE Result_Display SHALL render the fraud decision outcome according to the decision type (ALLOW, REVIEW, or BLOCK) as specified in Requirements 4, 5, and 6.
4. WHEN the Fraud_Detection_API returns a successful response, THE Payment_Form SHALL hide the loading indicator and re-enable the submit button.
5. IF the Fraud_Detection_API returns an HTTP error status, THEN THE Result_Display SHALL display an error message indicating the HTTP status code and error description returned by the API.
6. IF the Fraud_Detection_API request times out after 10 seconds, THEN THE Result_Display SHALL display a timeout error message instructing the user to try again.
7. IF a network error occurs during submission, THEN THE Result_Display SHALL display a connectivity error message instructing the user to check their connection and try again.
8. IF the Fraud_Detection_API returns an HTTP error status, a timeout, or a network error, THEN THE Payment_Form SHALL hide the loading indicator and re-enable the submit button.

### Requirement 4: ALLOW Decision Display

**User Story:** As a payment operator, I want to see a clear confirmation when a payment passes fraud checks, so that I know the payment is approved.

#### Acceptance Criteria

1. WHEN the Fraud_Detection_API returns an ALLOW decision, THE Result_Display SHALL display a success indicator with the text "Payment Approved".
2. WHEN the Fraud_Detection_API returns an ALLOW decision, THE Result_Display SHALL display the risk score as a numeric integer value labeled "Risk Score".
3. WHEN the Fraud_Detection_API returns an ALLOW decision, THE Result_Display SHALL display the risk breakdown with each component individually labeled: "Amount Score", "CoP Score", "Behavioural Score", and "Channel Score", each showing its numeric integer value.
4. WHEN the Fraud_Detection_API returns an ALLOW decision, THE Result_Display SHALL visually distinguish the success indicator from the warning indicator used for REVIEW decisions and the danger indicator used for BLOCK decisions.

### Requirement 5: REVIEW Decision Display

**User Story:** As a payment operator, I want to see the reasons a payment was held for review and have the option to proceed, so that I can make an informed decision on whether to approve it.

#### Acceptance Criteria

1. WHEN the Fraud_Detection_API returns a REVIEW decision, THE Result_Display SHALL display a warning indicator with the text "Payment Held for Review".
2. WHEN the Fraud_Detection_API returns a REVIEW decision, THE Result_Display SHALL display the risk score value as an integer between 0 and 100.
3. WHEN the Fraud_Detection_API returns a REVIEW decision, THE Result_Display SHALL display the risk breakdown showing amount score, CoP score, behavioural score, and channel score.
4. WHEN the Fraud_Detection_API returns a REVIEW decision, THE Result_Display SHALL display each Risk_Factor as a list item showing the category and explanation.
5. WHEN the Fraud_Detection_API returns a REVIEW decision, THE Result_Display SHALL display a "Confirm Payment" button to allow the user to proceed with the payment.
6. WHEN the user clicks the "Confirm Payment" button, THE Result_Display SHALL disable the "Confirm Payment" button, display a loading indicator, and send a confirmation request to the Fraud_Detection_API including the messageId from the original decision response.
7. WHEN the Fraud_Detection_API returns a successful confirmation response, THE Result_Display SHALL hide the loading indicator and display a success message "Payment confirmed and submitted for processing".
8. IF the confirmation request to the Fraud_Detection_API fails or times out after 10 seconds, THEN THE Result_Display SHALL hide the loading indicator, re-enable the "Confirm Payment" button, and display an error message indicating the confirmation failed and the user may retry.

### Requirement 6: BLOCK Decision Display

**User Story:** As a payment operator, I want to see why a payment was blocked, so that I understand the fraud risk and know the payment cannot proceed.

#### Acceptance Criteria

1. WHEN the Fraud_Detection_API returns a BLOCK decision, THE Result_Display SHALL display a danger indicator with the text "Payment Blocked".
2. WHEN the Fraud_Detection_API returns a BLOCK decision, THE Result_Display SHALL display the risk score as an integer value between 0 and 100.
3. WHEN the Fraud_Detection_API returns a BLOCK decision, THE Result_Display SHALL display the risk breakdown showing the amount score, CoP score, behavioural score, and channel score each as an integer value between 0 and 100.
4. WHEN the Fraud_Detection_API returns a BLOCK decision with one or more Risk_Factors, THE Result_Display SHALL display each Risk_Factor as a list item showing the category and explanation.
5. IF the Fraud_Detection_API returns a BLOCK decision with an empty Risk_Factors list, THEN THE Result_Display SHALL hide the risk factors section.
6. WHEN the Fraud_Detection_API returns a BLOCK decision, THE Result_Display SHALL NOT display a "Confirm Payment" button.
7. WHEN the Fraud_Detection_API returns a BLOCK decision, THE Result_Display SHALL display a message "This payment cannot proceed due to fraud risk".

### Requirement 7: New Payment Reset

**User Story:** As a payment operator, I want to start a new payment check after viewing a result, so that I can process multiple payments in sequence.

#### Acceptance Criteria

1. WHEN the Result_Display is showing a decision outcome (ALLOW, REVIEW, or BLOCK) or an error message, THE Result_Display SHALL display a "New Payment" button.
2. WHEN the user clicks the "New Payment" button, THE Payment_Form SHALL reset all text input fields to empty, reset dropdown selections (Channel_Type and CoP_Result) to no selection, and re-enable the submit button.
3. WHEN the user clicks the "New Payment" button, THE Result_Display SHALL be hidden.
