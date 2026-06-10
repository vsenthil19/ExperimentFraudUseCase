# Implementation Plan: Payment Fraud UI

## Overview

This plan implements a vanilla JavaScript single-page application for submitting UK Faster Payments to the fraud detection API. The UI consists of modular JS files (`form.js`, `validation.js`, `api.js`, `result.js`, `app.js`) plus a single `index.html` with embedded CSS, all served from a `frontend/` directory. Property-based tests for validation logic are written in Java using jqwik.

## Tasks

- [x] 1. Create HTML structure and CSS styling
  - [x] 1.1 Create `frontend/index.html` with complete page structure
    - Create the HTML document with all form fields: debtor sort code, debtor account number, debtor account name, creditor sort code, creditor account number, creditor account name, amount, payment reference, channel type dropdown, CoP result dropdown, CoP matched name
    - Include the "Check Payment" submit button
    - Add a result display container (hidden by default)
    - Add a "New Payment" button in the result section
    - Add ARIA attributes for accessibility (aria-describedby for error messages)
    - Embed all CSS styles in a `<style>` block within the `<head>`
    - Style the form with clear field labels, input styling, and dropdown styling
    - Define CSS classes for success (green/ALLOW), warning (amber/REVIEW), and danger (red/BLOCK) indicators
    - Define CSS for validation error messages (red text below fields)
    - Define CSS for loading states (disabled button, spinner indicator)
    - Include `<script>` tags loading modules in order: `validation.js`, `api.js`, `form.js`, `result.js`, `app.js`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 4.4, 7.1_

- [x] 2. Implement Validation Module
  - [x] 2.1 Create `frontend/validation.js` with pure validation functions
    - Implement `Validator.validate(formData)` that returns `{ valid: boolean, errors: [] }`
    - Implement sort code validation: required check, 6-digit format check (accepts NN-NN-NN or NNNNNN)
    - Implement account number validation: required check, exactly 8 digits check
    - Implement amount validation: required check, numeric check, range check (0.01–999999999.99), max 2 decimal places check
    - Implement channel type validation: required selection check
    - Collect ALL errors simultaneously (never short-circuit on first failure)
    - Return structured `{ field, message }` error objects matching the exact messages from requirements
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14_

  - [ ]* 2.2 Write property test for sort code validation
    - Create `src/test/java/property/com/frauddetection/ui/SortCodeValidationPropertyTest.java`
    - Use jqwik to generate random strings (0–20 chars, mix of digits/alpha/symbols)
    - Assert: accepted if and only if input is exactly 6 digits or formatted NN-NN-NN
    - Implement a Java port of the sort code validation logic for property testing
    - Minimum 100 iterations
    - **Property 1: Sort code validation**
    - **Validates: Requirements 2.2, 2.6**

  - [ ]* 2.3 Write property test for account number validation
    - Create `src/test/java/property/com/frauddetection/ui/AccountNumberValidationPropertyTest.java`
    - Use jqwik to generate random strings (0–20 chars, mix of digits/alpha/symbols)
    - Assert: accepted if and only if input is exactly 8 digit characters
    - Implement a Java port of the account number validation logic for property testing
    - Minimum 100 iterations
    - **Property 2: Account number validation**
    - **Validates: Requirements 2.4, 2.8**

  - [ ]* 2.4 Write property test for amount validation
    - Create `src/test/java/property/com/frauddetection/ui/AmountValidationPropertyTest.java`
    - Use jqwik to generate random strings (numbers, text, edge values, varying decimals)
    - Assert: accepted if and only if input is numeric, in range [0.01, 999999999.99], and at most 2 decimal places
    - Implement a Java port of the amount validation logic for property testing
    - Minimum 100 iterations
    - **Property 3: Amount validation**
    - **Validates: Requirements 2.9, 2.10, 2.11**

  - [ ]* 2.5 Write property test for simultaneous error reporting
    - Create `src/test/java/property/com/frauddetection/ui/SimultaneousErrorsPropertyTest.java`
    - Use jqwik to generate form data with 0–6 randomly invalidated fields
    - Assert: number of errors returned equals number of independently invalid fields
    - Minimum 100 iterations
    - **Property 4: All validation errors returned simultaneously**
    - **Validates: Requirements 2.13**

- [x] 3. Implement API Client Module
  - [x] 3.1 Create `frontend/api.js` with HTTP communication logic
    - Implement `ApiClient.init(baseUrl)` to store the API base URL
    - Implement `ApiClient.submitPayment(request)` that POSTs to `/fraud-check`
    - Implement `ApiClient.confirmPayment(messageId)` that POSTs to `/confirm-payment`
    - Use `fetch` with `AbortController` for 10-second timeout
    - Return structured error objects: `{ type: "http"|"timeout"|"network", statusCode?, description? }`
    - Parse successful JSON responses and return as resolved promises
    - Distinguish HTTP errors (non-2xx), timeout errors (AbortController signal), and network errors (TypeError from fetch)
    - _Requirements: 3.1, 3.5, 3.6, 3.7_

  - [ ]* 3.2 Write property test for request payload construction
    - Create `src/test/java/property/com/frauddetection/ui/RequestPayloadPropertyTest.java`
    - Use jqwik to generate valid form data with random values within constraints
    - Assert: constructed payload contains valid UUID v4, ISO 8601 timestamp, currency "GBP", all fields mapped correctly
    - Minimum 100 iterations
    - **Property 5: Request payload construction**
    - **Validates: Requirements 3.1**

- [x] 4. Implement Result Display Module
  - [x] 4.1 Create `frontend/result.js` with decision rendering logic
    - Implement `ResultDisplay.init(containerElement)` to bind the result container
    - Implement `ResultDisplay.renderAllow(response)` with green success styling and "Payment Approved" text
    - Implement `ResultDisplay.renderReview(response, onConfirm)` with amber warning styling, "Payment Held for Review" text, risk factors list, and "Confirm Payment" button
    - Implement `ResultDisplay.renderBlock(response)` with red danger styling, "Payment Blocked" text, risk factors list (hidden if empty), "This payment cannot proceed due to fraud risk" message, and no confirm button
    - Implement `ResultDisplay.renderError(error)` for HTTP/timeout/network errors
    - Implement `ResultDisplay.showConfirmationSuccess()` showing "Payment confirmed and submitted for processing"
    - Implement `ResultDisplay.showConfirmationError()` showing confirmation failure with retry
    - Implement `ResultDisplay.setConfirmLoading(isLoading)` to toggle confirm button state
    - Display risk score labeled "Risk Score" for all decision types
    - Display risk breakdown with labels: "Amount Score", "CoP Score", "Behavioural Score", "Channel Score"
    - Display risk factors as list items with category and explanation
    - Include "New Payment" button in all result states
    - Implement `ResultDisplay.hide()` and `ResultDisplay.show()`
    - _Requirements: 3.3, 3.5, 3.6, 3.7, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 7.1, 7.3_

  - [ ]* 4.2 Write property test for risk score rendering
    - Create `src/test/java/property/com/frauddetection/ui/RiskScoreRenderingPropertyTest.java`
    - Use jqwik to generate random FraudDecisionResponse with score 0–100 and all decision types
    - Assert: rendered output contains the numeric risk score value labeled "Risk Score"
    - Minimum 100 iterations
    - **Property 6: Risk score rendering**
    - **Validates: Requirements 4.2, 5.2, 6.2**

  - [ ]* 4.3 Write property test for risk breakdown rendering
    - Create `src/test/java/property/com/frauddetection/ui/RiskBreakdownRenderingPropertyTest.java`
    - Use jqwik to generate random FraudDecisionResponse with 4 random component scores
    - Assert: rendered output contains all four breakdown values with their respective labels
    - Minimum 100 iterations
    - **Property 7: Risk breakdown rendering**
    - **Validates: Requirements 4.3, 5.3, 6.3**

  - [ ]* 4.4 Write property test for risk factor list rendering
    - Create `src/test/java/property/com/frauddetection/ui/RiskFactorRenderingPropertyTest.java`
    - Use jqwik to generate random responses with 1–10 risk factors (random categories/explanations)
    - Assert: every risk factor's category and explanation appears as a visible list item
    - Minimum 100 iterations
    - **Property 8: Risk factor list rendering**
    - **Validates: Requirements 5.4, 6.4**

- [x] 5. Implement Payment Form Module
  - [x] 5.1 Create `frontend/form.js` with form management logic
    - Implement `PaymentForm.init(formElement, onSubmit)` to bind the form and prevent default submit
    - Implement `PaymentForm.getFormData()` returning the structured form data object
    - Implement `PaymentForm.setLoading(isLoading)` to disable submit button and show loading indicator
    - Implement `PaymentForm.clearErrors()` to remove all validation error displays
    - Implement `PaymentForm.showErrors(errors)` to display inline error messages next to fields using aria-describedby
    - Implement `PaymentForm.reset()` to clear all text inputs, reset dropdowns to no selection, enable submit button
    - Implement `PaymentForm.hide()` and `PaymentForm.show()`
    - _Requirements: 1.9, 2.13, 2.14, 3.2, 3.4, 3.8, 7.2, 7.3_

  - [ ]* 5.2 Write property test for form reset
    - Create `src/test/java/property/com/frauddetection/ui/FormResetPropertyTest.java`
    - Use jqwik to generate form data pre-populated with random values
    - Assert: after reset, all text inputs are empty, all dropdowns have no selection, submit button is enabled
    - Minimum 100 iterations
    - **Property 9: Form reset clears all state**
    - **Validates: Requirements 7.2**

- [x] 6. Implement App Controller and wire modules together
  - [x] 6.1 Create `frontend/app.js` with application orchestration
    - Implement `App.init(config)` that initializes all modules with DOM elements
    - Wire form submission: call `Validator.validate()`, show errors or call `ApiClient.submitPayment()`
    - Build FasterPaymentRequest payload: generate UUID v4 messageId, ISO 8601 timestamp, hardcode "GBP" currency, strip hyphens from sort codes, set channel optional fields to null
    - Wire result display: route ALLOW/REVIEW/BLOCK responses to correct render methods
    - Wire "Confirm Payment" button: call `ApiClient.confirmPayment(messageId)`, handle success/error
    - Wire "New Payment" button: call `PaymentForm.reset()`, `PaymentForm.show()`, `ResultDisplay.hide()`
    - Wire loading states: disable button on submit, re-enable on response/error
    - Add DOMContentLoaded event listener to auto-initialize with a configurable API base URL
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 5.6, 5.7, 5.8, 7.2, 7.3_

- [x] 7. Checkpoint - Verify UI functionality
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests use jqwik (already in build.gradle) and validate universal correctness properties
- Property tests for validation logic implement a Java port of the JavaScript validation rules to verify correctness invariants
- Property tests for rendering verify that generated HTML output contains expected content
- The frontend uses no build tooling — files are plain JavaScript loaded via script tags
- Sort codes are displayed as NN-NN-NN but transmitted without hyphens to the API

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "3.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "2.5", "3.2", "4.1"] },
    { "id": 3, "tasks": ["4.2", "4.3", "4.4", "5.1"] },
    { "id": 4, "tasks": ["5.2", "6.1"] }
  ]
}
```
