# Technical Challenge

As a software architect, we are going to define the following technical challenge using Elixir and Phoenix as the framework—or alternatively, identify possible services, best practices, and we will track the project phases using github-issue (for issue and project tracking).

We will implement an MVP with the following characteristics:

## 1. Context

Our company is a **fintech operating in 6 countries** across Latin America and Europe:

- Spain (ES)
- Portugal (PT)
- Italy (IT)
- Mexico (MX)
- Colombia (CO)
- Brazil (BR)

Each country has different operational, regulatory, and banking provider variations. The goal is to build a core system that supports credit applications across multiple countries in an extensible manner **and is prepared to operate at a large scale**.

## 2. Objective of the Challenge

Build an MVP that allows to:

1. Create credit applications.
2. Validate country-specific business rules.
3. Integrate with different banking providers based on the country.
4. Query individual applications.
5. List applications filtered by country.
6. Update the status of an application.
7. Process business logic in the background and in parallel.
8. Display information in (near) real-time on the frontend.

You must select **at least two countries** from the list above for your main implementation. You may add more if you wish.

## 3. Required Functionality

## 3.1 Application Creation

Each application must include:

- Country
- Full name
- Identity document
- Requested amount
- Monthly income
- Application date
- Initial status
- Banking information obtained from the corresponding provider

The creation of an application must trigger additional logic (for example: risk validation, auditing, or background processing).

## 3.2 Rule Validation by Country

Each country has specific rules that must be applied during the creation or update of a credit application. Implement the following minimum rules, considering that in each case it is required to verify that the document and associated information are reasonably valid according to the corresponding country:

## **Spain (ES)** - Required document: DNI.

- The application must include document verifications.

- If the requested amount exceeds a threshold defined by you, it must be marked as subject to additional review.

## **Portugal (PT)** - Required document: NIF.

- Some form of document verification must exist.

- There must be at least one rule related to monthly income and the requested amount.

## **Italy (IT)** - Required document: Codice Fiscale.

- The application must include document verifications.

- There must be a rule related to financial stability or income.

## **Mexico (MX)** - Required document: CURP.

- Corresponding document verification.

- There must be a rule based on the ratio between monthly income and the requested amount.

## **Colombia (CO)** - Required document: Cédula de Ciudadanía (CC).

- Consider the ratio between total debt (data from the banking provider) and monthly income.

## **Brazil (BR)** - Required document: CPF.

- Corresponding document verification.

- A rule related to credit score or payment capacity must be included.

You can extend or add rules if you deem it necessary.

## 3.3 Integration with Banking Provider by Country

Each country uses a different banking provider to obtain customer information. These providers may have differences in how they deliver information, as well as the specific data they provide.

Your solution must account for these variations between countries and allow the application to process the necessary banking information to evaluate each application.

## 3.4 Application Statuses

Define an appropriate status flow per country. The design should allow new statuses or flows to be added in the future.

Status transitions can trigger additional logic (for example: notifications, re-evaluations, or auditing).

## 3.5 Querying an Application

The application must allow retrieving the full data of a specific application using its identifier.

## 3.6 Listing Applications

There must be a way to obtain a list of applications, with the ability to filter them by country and other criteria you consider relevant (for example: status, date range).

## 3.7 Asynchronous Processing and Events

The system must incorporate **asynchronous processing** so that certain tasks do not block the main API flow. Consider, for example:

- Risk evaluation processes.

- Generation of audit logs.

- Notifications to other systems.

Requirements:

- Use native database capabilities (for example, functions and trigger mechanisms in PostgreSQL) to react to data changes when you deem it appropriate.

- Include at least one flow where a database operation generates work to be processed asynchronously (for example: in a job queue).

## 3.8 Webhooks and External Processes

Define at least one flow where:

- Your system **receives** information from an external system via webhook **or** sends a notification to a simulated external endpoint to complete part of the flow.

This flow must be integrated with the applications model (for example: status update, data confirmation, or external event logging).

## 3.9 Concurrency and Parallel Processing

The design must allow multiple processes or workers to run in parallel (for example, multiple queue consumers or processes reacting to events) without generating evident data inconsistencies.

It is not necessary to simulate real high concurrency, but you must show how your solution would allow scaling the number of processes or instances executing concurrent business logic.

## 3.10 Real-time Updates on the Frontend

Include a view that displays relevant information (for example, the list of applications or status changes) and that can be updated in near real-time when changes occur in the system.

You can use **Socket.IO or any equivalent** bidirectional communication technology to keep the interface synchronized with backend events.

## 4. Non-Functional Requirements

## 4.1 Architecture and Levels of Responsibility in Code

- Modular and extensible code.

- Clear separation of concerns into multiple layers (for example: controllers, services, repositories, integration, etc.).

- A design that allows adding countries, providers, or new flows without disruptive changes across the entire system.

## 4.2 API Security

- Secure handling of PII.

- Avoid exposing sensitive banking data.

- Implement at least one authentication mechanism based on **JWT** or an equivalent strategy.

- Consider basic authorization (who can see or modify what).

## 4.3 Observability

- Clear and structured logs.

- Explicit error handling.

- Sufficient logs to understand what happened in an asynchronous flow (for example, queued jobs, webhooks, status changes).

## 4.4 Reproducibility

- The solution must be easy to run.

- Include clear instructions in the README.

- The evaluator must be able to install and run it in **less than 5 minutes** (assuming standard tools are installed).

## 4.5 Scalability and Large Data Volume Management

Design with the mindset that the system may eventually handle **millions of credit applications**.

Include an analysis in the README regarding:

- Recommended indexes.

- How you would structure tables to handle large volumes (partitioning, strategies you consider).

- Critical queries and how you would avoid bottlenecks.

- Possible archiving or compression strategies if you consider them necessary.

It is not necessary to create millions of records, but you must demonstrate that the design accounts for them.

## 4.6 Queues and Job Queueing

The system must be capable of queueing tasks for asynchronous execution (for example, through a message queue or a jobs table).

- Explain in the README what technology you use (or simulate) for the queue.

- Show how at least one type of job is produced and consumed.

## 4.7 Caching

Incorporate some form of **caching** to improve the response time of a part of the system (for example, reading applications, evaluation results, catalogs, etc.).

- Indicate what you decide to cache and why.

- Describe in the README what invalidation strategy you use (even if it is a simple one).

## 4.8 Deployment (Kubernetes / k8s)

Include configuration files to deploy your solution in a **Kubernetes-type** environment. A real deployment is not necessary, but you must include:

- Basic manifests (YAML) for the main components (for example: backend, frontend, database if included in the environment, workers).

- Necessary environment variables and configuration.

- Any special considerations (for example, services, ingress, etc.).

If you use another related tool (Helm, kustomize, etc.), describe it in the README.

## 5. Required Frontend

Include an interface that allows to:

- Create applications.

- View the list of applications.

- View details.

- Update status.

- Visualize relevant changes (for example, status changes or results of asynchronous processes) in near real-time.

The design can be simple, but it must display the information clearly and handle errors properly.

## 6. Deliverables

1. A repository containing the backend, frontend, and code related to asynchronous processing, queues, cache, and deployment.

2. A README featuring:

   - Clear instructions to install and run the solution.
   - Assumptions.
   - Data model.
   - Technical decisions.
   - Security considerations.
   - Analysis of scalability and handling of large data volumes.
   - Description of the concurrency, queues, cache, and webhooks strategy.

3. **Configuration files for Kubernetes deployment**.

4. **Makefile or Justfile** with commands to simplify frequent tasks (for example: `make run`, `make test`, `make migrate`, `make deploy`, or equivalents).

Optional Extras:

- Implementation of additional countries.
- Metrics and dashboards.
- Detailed change auditing.
- Advanced resilience mechanisms against provider or queue failures.

## 8. Delivery

Submit a public repository with your entire solution.

## 9. Glossary

**PII:** “Personally Identifiable Information”, or **personal information that can be used to directly or indirectly identify an individual**.