---
inclusion: auto
---

# LocalStack Integration Testing

When writing or running integration tests that involve AWS services, ALL AWS components must be stood up locally using LocalStack via Testcontainers. Never use real AWS credentials or endpoints for validation.

## Required Setup

### LocalStack Container Configuration

Use Testcontainers with the LocalStack image. Declare all services the test needs:

```java
@Container
static LocalStackContainer localStack = new LocalStackContainer(
        DockerImageName.parse("localstack/localstack:3.4"))
        .withServices(
            LocalStackContainer.Service.DYNAMODB,
            LocalStackContainer.Service.S3,
            LocalStackContainer.Service.SQS,
            LocalStackContainer.Service.EVENTBRIDGE
        );
```

### AWS Client Configuration

All AWS SDK clients MUST point to the LocalStack endpoint with test credentials:

```java
DynamoDbClient dynamoDbClient = DynamoDbClient.builder()
    .endpointOverride(localStack.getEndpointOverride(LocalStackContainer.Service.DYNAMODB))
    .credentialsProvider(StaticCredentialsProvider.create(
        AwsBasicCredentials.create(localStack.getAccessKey(), localStack.getSecretKey())))
    .region(Region.of(localStack.getRegion()))
    .build();
```

Apply the same pattern for S3Client, SqsClient, EventBridgeClient, and any other AWS service clients.

### Infrastructure Provisioning

Before tests run, create all required AWS resources on LocalStack:

1. **DynamoDB** — Create tables using `DynamoDbConfig.createTable()` which sets up the single-table design with GSI
2. **S3** — Create buckets: `s3Client.createBucket(CreateBucketRequest.builder().bucket(BUCKET_NAME).build())`
3. **EventBridge** — Create event bus: `eventBridgeClient.createEventBus(CreateEventBusRequest.builder().name(EVENT_BUS_NAME).build())`
4. **SQS** — Create queues for verifying EventBridge event delivery
5. **EventBridge Rules** — Create rules and targets to route events to SQS for verification

### EventBridge Verification Pattern

To verify events are published correctly, set up an SQS queue as an EventBridge target:

1. Create an SQS queue
2. Create an EventBridge rule matching the event pattern
3. Add the SQS queue as a target for the rule
4. After invoking the handler, poll the SQS queue to verify event delivery

## Rules

- Never hardcode AWS endpoints — always derive from `localStack.getEndpointOverride()`
- Always use `forcePathStyle(true)` for S3 clients pointing to LocalStack
- Use `@Testcontainers` and `@Container` annotations for lifecycle management
- Provision all infrastructure in `@BeforeAll` setup methods
- Clean up or isolate state between tests (drain queues, use unique IDs)
- Integration tests go in `src/test/java/integration/` and run via `./gradlew integrationTest`
- Integration tests are excluded from the default `./gradlew test` task
- Allow async operations (event publishing) time to complete before assertions — use `Thread.sleep()` or polling with timeout

## AWS Services Used in This Project

| Service | Purpose | LocalStack Service Enum |
|---------|---------|------------------------|
| DynamoDB | Customer profiles, beneficiary registry, audit records | `Service.DYNAMODB` |
| EventBridge | Async event publishing (DecisionMade, TransactionCompleted) | `Service.EVENTBRIDGE` |
| S3 | Long-term audit record archival | `Service.S3` |
| SQS | EventBridge target for test verification | `Service.SQS` |

## DynamoDB Table Setup

The project uses a single-table design. Create it with:

```java
DynamoDbConfig config = new DynamoDbConfig(dynamoDbClient, "FraudDetection");
config.createTable();
```

This creates the table with PK/SK keys and the `DecisionByDate` GSI automatically.
