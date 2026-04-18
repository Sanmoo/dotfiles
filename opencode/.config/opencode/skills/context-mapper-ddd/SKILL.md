---
name: context-mapper-ddd
description: Model domains using DDD tactical and strategic patterns in Context Mapper Language (CML) syntax. Use when user asks to "model a domain", "create bounded contexts", "design aggregates", "DDD modeling", "modelar dominio", "criar bounded contexts", "modelar agregados", "context mapper", or needs to express Entities, Value Objects, Domain Events, Commands, Services, Repositories, Aggregates, Bounded Contexts, Domains, or Subdomains in CML. Do NOT use for code generation, database schema design, or UML diagrams.
---

# Context Mapper DDD Modeler

You are an expert in Domain-Driven Design (DDD) who models domains using the Context Mapper Language (CML) syntax. You produce syntactically correct CML that can be used directly with the ContextMapper toolchain or embedded in documentation.

Reference: https://contextmapper.org/docs/tactic-ddd/

## When to Use This Skill

Use this skill when:

- User asks to "model a domain", "design a domain model", or "DDD modeling"
- User asks to "modelar um dominio", "criar modelo de dominio", or "modelagem DDD"
- User wants to define Bounded Contexts, Aggregates, Entities, Value Objects, Domain Events, Commands, Services, or Repositories
- User asks to "create a context map", "define bounded contexts", or "map domain boundaries"
- User provides a domain description and wants it expressed in CML syntax
- User wants to iterate on an existing CML model (add aggregates, refine entities, etc.)
- User mentions "context mapper" or "CML" explicitly

Do NOT use this skill when:

- User wants code generation (Java, TypeScript, etc.) from a domain model
- User wants database schema or ERD diagrams
- User wants UML class diagrams (suggest PlantUML generator from ContextMapper instead)
- User wants API design (suggest MDSL generator from ContextMapper instead)

## Language Adaptation

**CRITICAL**: Always generate CML models and surrounding explanations in the **same language as the user's request**. Detect the language automatically from the user's input.

**Translation Guidelines**:

- Translate all prose, explanations, and comments to match user's language
- **Keep all CML keywords in English** (they are part of the syntax): `Entity`, `ValueObject`, `DomainEvent`, `Command`, `Service`, `Repository`, `Aggregate`, `BoundedContext`, `Domain`, `Subdomain`, `aggregateRoot`, `def`, `key`, etc.
- Keep domain concept names (type names, attribute names) in the language that best fits the domain -- typically English for international projects, but follow the user's convention
- CML comments use `/* ... */` or `//` and should be in the user's language

## CML Syntax Reference

This section is the authoritative reference you must follow when generating CML. All syntax rules come from the ContextMapper documentation.

---

### 1. Domain and Subdomain

Domains are top-level containers that group Subdomains. Bounded Contexts implement Domains or Subdomains.

```cml
Domain InsuranceDomain {
  domainVisionStatement = "Insurance domain vision statement ..."

  Subdomain CustomerManagementDomain {
    type = CORE_DOMAIN
    domainVisionStatement = "Subdomain managing everything customer-related."

    Entity Customer {
      String firstname
      String familyname
    }
  }

  Subdomain ContractManagementDomain {
    type = SUPPORTING_DOMAIN
  }

  Subdomain PrintingDomain {
    type = GENERIC_SUBDOMAIN
  }
}
```

**Subdomain types** (use the `type` keyword):

| Type | Meaning |
|------|---------|
| `CORE_DOMAIN` | The core differentiator of the business |
| `SUPPORTING_DOMAIN` | Supports the core but is not the differentiator |
| `GENERIC_SUBDOMAIN` | Generic functionality, could be bought off-the-shelf |

**Subdomain features** (optional):

- `domainVisionStatement` -- free text describing the subdomain's purpose
- `supports` keyword -- references UserStory or UseCase declarations
- `Entity` -- simple entities for business modeling (only entities allowed inside subdomains; no Aggregates or other tactic patterns)

**Important**: Entities inside Subdomains are for business modeling only. Generators use the domain model inside Bounded Contexts, not Subdomains.

---

### 2. Bounded Context

Bounded Contexts are declared at the root level of a CML file. They contain Aggregates (and optionally Modules).

```cml
BoundedContext CustomerManagementContext implements CustomerManagementDomain {
  type = FEATURE
  domainVisionStatement = "The customer management context is responsible for ..."
  implementationTechnology = "Java, JEE Application"
  responsibilities = "Customers", "Addresses"
  knowledgeLevel = CONCRETE

  Aggregate Customers {
    Entity Customer {
      aggregateRoot

      - SocialInsuranceNumber sin
      String firstname
      String lastname
      - List<Address> addresses
    }
  }

  Aggregate Addresses {
    Entity Address {
      aggregateRoot
      String street
      int postalCode
      String city
    }
  }
}
```

**Bounded Context attributes** (all optional):

| Attribute | Values | Description |
|-----------|--------|-------------|
| `type` | `FEATURE`, `APPLICATION`, `SYSTEM`, `TEAM` | The viewpoint of the bounded context |
| `domainVisionStatement` | free text | Vision statement (DDD pattern) |
| `implementationTechnology` | free text | How the context is implemented |
| `responsibilities` | comma-separated strings | Responsibility Layers pattern |
| `knowledgeLevel` | `CONCRETE`, `META` | Knowledge Level pattern |

**`implements` keyword**: References a Domain or comma-separated list of Subdomains.

**`refines` keyword**: One bounded context can refine another (inheritance-like relationship).

**`realizes` keyword**: Only for `type = TEAM` -- specifies which bounded context the team implements.

```cml
BoundedContext CustomerBackendTeam implements CustomerManagementDomain realizes CustomerManagementContext {
  type = TEAM
  domainVisionStatement = "This team is responsible for ..."
}
```

**Bounded Context names must be unique within the entire CML model.**

**The `=` sign for attribute assignment is always optional and can be omitted.**

---

### 3. Aggregate

Aggregates live inside Bounded Contexts. They contain Entities, Value Objects, Domain Events, Commands, Services, and enums.

```cml
Aggregate Contract {
  responsibilities = "Contracts", "Policies"
  knowledgeLevel = CONCRETE

  Entity Contract {
    aggregateRoot

    - ContractId identifier
    - Customer client
    - List<Product> products
  }

  ValueObject ContractId {
    int contractId key
  }

  Entity Policy {
    int policyNr
    - Contract contract
    BigDecimal price
  }

  Service ContractService {
    @ContractId createContract(@Contract contract) : write [ -> CREATED];
    @Contract getContract(@ContractId contractId) : read-only;
    boolean createPolicy(@ContractId contractId) : write [ CREATED -> POLICY_CREATED ];
  }

  enum States {
    aggregateLifecycle
    CREATED, POLICY_CREATED, RECALLED
  }
}
```

**Aggregate attributes** (all optional):

| Attribute | Values | Description |
|-----------|--------|-------------|
| `responsibilities` | comma-separated strings | Responsibility Layers |
| `knowledgeLevel` | `CONCRETE`, `META` | Knowledge Level |
| `owner` | reference to a TEAM bounded context | Which team owns this aggregate |
| `useCases` | comma-separated UseCase references | Features supported |
| `userStories` | comma-separated UserStory references | Features supported |
| `features` | comma-separated UseCase/UserStory refs | Shorthand for both |
| `likelihoodForChange` | `RARELY`, `NORMAL`, `OFTEN` | Structural volatility |
| `contentVolatility` | `RARELY`, `NORMAL`, `OFTEN` | Content change frequency |
| `availabilityCriticality` | `LOW`, `NORMAL`, `HIGH` | Availability requirements |
| `consistencyCriticality` | `LOW`, `NORMAL`, `HIGH` | Consistency requirements |
| `storageSimilarity` | `TINY`, `NORMAL`, `HUGE` | Storage characteristics |
| `securityCriticality` | `LOW`, `NORMAL`, `HIGH` | Security requirements |
| `securityZone` | free text string | Security zone classification |
| `securityAccessGroup` | free text string | Access group classification |

**Aggregate names must be unique within the entire CML model.**

---

### 4. Entity

Entities are declared with the `Entity` keyword. Mark the aggregate root with `aggregateRoot`.

```cml
Entity Customer {
  aggregateRoot

  - SocialInsuranceNumber sin
  String firstname
  String lastname
  - List<Address> addresses

  def @AddressId createAddress(@Address address);
  def void changeCustomer(@Customer customer, @Address address);
}
```

**Attribute syntax**:

```
// Primitive type attribute
String firstname

// Collection attribute
List<String> tags

// Reference to another declared type (use the - prefix)
- Address homeAddress
- List<Address> addresses
- Set<Role> roles

// Key attribute (marks a field as the identity key)
int customerId key

// Nullable attribute
nullable String middleName
```

**Primitive types available**: `String`, `int`, `Integer`, `long`, `Long`, `boolean`, `Boolean`, `Date`, `DateTime`, `Timestamp`, `BigDecimal`, `BigInteger`, `double`, `Double`, `float`, `Float`, `Key`, `Blob`, `Clob`, `Object`.

**Collection types**: `List`, `Set`, `Bag`, `Collection`.

**Type References** -- the `-` (minus) prefix:

- Use `-` before an attribute type to reference another declared type (Entity, ValueObject, DomainEvent, etc.)
- Without `-`, the type is treated as an abstract/undeclared type (no validation)
- The language validates that referenced types exist in the model

---

### 5. Value Object

Value Objects are declared with the `ValueObject` keyword. They have no identity -- equality is based on attribute values.

```cml
ValueObject Address {
  String street
  int postalCode
  String city
}

ValueObject Money {
  BigDecimal amount
  String currency key
}

ValueObject SocialInsuranceNumber {
  String sin key
}
```

Attributes and methods follow the same syntax as Entity (including `-` references, `def` methods, `key`).

---

### 6. Domain Event

Domain Events represent something that happened in the domain. Declared with `DomainEvent` (or `Event`).

```cml
DomainEvent CustomerAddressChanged {
  - Customer customer
  - Address newAddress
  Date changedAt
}

DomainEvent OrderPlaced {
  - OrderId orderId
  - List<OrderItem> items
  BigDecimal totalAmount
  Date placedAt
}

Event PaymentReceived {
  - PaymentId paymentId
  BigDecimal amount
  Date receivedAt
}
```

Attributes and methods follow the same syntax as Entity.

---

### 7. Command

Commands represent an intention to change something. Declared with `Command` (or `CommandEvent`).

```cml
Command PlaceOrder {
  - CustomerId customerId
  - List<OrderItem> items
  - Address shippingAddress
}

Command RejectClaim {
  - Claim claim2Reject
  - Employee decisionMaker
  String reason4Rejection
}
```

Attributes and methods follow the same syntax as Entity.

---

### 8. Service

Domain Services contain operations. Declared with the `Service` keyword. Services can live inside Aggregates or directly inside Bounded Contexts.

**IMPORTANT**: Operations in Services do NOT use the `def` keyword (unlike Entity/VO/Event methods).

```cml
Service RoutingService {
  List<@Itinerary> fetchRoutesForSpecification(@RouteSpecification routeSpecification)
    throws LocationNotFoundException;
}

Service CustomerService {
  @CustomerId createCustomer(@Customer customer) : write [ -> CREATED];
  @Customer getCustomer(@CustomerId customerId) : read-only;
  boolean updateCustomer(@Customer customer) : write;
}
```

**Operation syntax details**:

- Return type comes first, then method name, then parameters in parentheses
- Use `@` to reference declared types in parameters and return types
- Without `@`, types are treated as abstract/undeclared
- `throws` keyword to declare exceptions
- `: read-only` or `: write` to classify operations
- `: write [ STATE1 -> STATE2 ]` to declare state transitions

---

### 9. Repository

Repositories provide data access for an Aggregate. Declared with the `Repository` keyword **inside the aggregate root Entity only**.

**IMPORTANT**: Only aggregate roots can contain Repositories. This is enforced by the language.

```cml
Entity Location {
  aggregateRoot

  PortCode portcode
  - UnLocode unLocode
  String name

  Repository LocationRepository {
    @Location find(@UnLocode unLocode);
    List<@Location> findAll();
    save(@Location location);
  }
}
```

Operations follow the same syntax as Service operations (no `def` keyword).

---

### 10. Methods / Operations Reference

Methods can appear in Entities, Value Objects, and Domain Events (with `def` keyword) or in Services and Repositories (without `def` keyword).

**In Entity / ValueObject / DomainEvent** -- use `def`:

```cml
Entity Order {
  aggregateRoot

  def @OrderId place(@OrderItems items);
  def void cancel();
  def boolean isActive();
}
```

**In Service / Repository** -- do NOT use `def`:

```cml
Service OrderService {
  @OrderId placeOrder(@Order order) : write [ -> PLACED];
  @Order getOrder(@OrderId orderId) : read-only;
}
```

**Reference syntax in operations**:

| Syntax | Meaning |
|--------|---------|
| `@TypeName` | Reference to a declared type (validated) |
| `TypeName` | Abstract type (not validated) |
| `List<@TypeName>` | Collection of referenced type |
| `void` | No return value |

---

### 11. Aggregate Lifecycle and State Transitions

Define aggregate states with an `enum` marked with `aggregateLifecycle`:

```cml
enum OrderStates {
  aggregateLifecycle
  DRAFT, PLACED, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
}
```

Then reference states in operations using `write` with square brackets:

```cml
Service OrderService {
  // Initial state (no left side)
  @OrderId createOrder(@Order order) : write [ -> DRAFT];

  // Simple transition
  void placeOrder(@OrderId orderId) : write [ DRAFT -> PLACED];

  // Multiple source states
  void cancelOrder(@OrderId orderId) : write [ DRAFT, PLACED -> CANCELLED];

  // Multiple target states (XOR -- one or the other, not both)
  void reviewOrder(@OrderId orderId) : write [ PLACED -> CONFIRMED X REJECTED];

  // End states (marked with *)
  void deliverOrder(@OrderId orderId) : write [ SHIPPED -> DELIVERED*];

  // Read-only (no state change)
  @Order getOrder(@OrderId orderId) : read-only;
}
```

**State transition syntax summary**:

| Pattern | Meaning |
|---------|---------|
| `-> STATE` | Initial transition (from nothing to STATE) |
| `A -> B` | From A to B |
| `A, B -> C` | From A or B to C |
| `A -> B X C` | From A to B or C (exclusive OR) |
| `A -> B*` | B is an end/terminal state |

---

### 12. Context Map (Basic)

Context Maps define relationships between Bounded Contexts. Declared at root level.

```cml
ContextMap InsuranceContextMap {
  type = SYSTEM_LANDSCAPE
  state = TO_BE

  contains CustomerManagementContext, PolicyManagementContext, PrintingContext

  CustomerManagementContext [D,C] <-> [U,S] PolicyManagementContext {
    implementationTechnology = "RESTful HTTP"
  }

  PolicyManagementContext [D,ACL] <- [U,OHS,PL] PrintingContext
}
```

**Relationship patterns** (between brackets):

| Abbreviation | Pattern |
|--------------|---------|
| `U` | Upstream |
| `D` | Downstream |
| `OHS` | Open Host Service |
| `PL` | Published Language |
| `ACL` | Anticorruption Layer |
| `CF` | Conformist |
| `S` | Supplier |
| `C` | Customer |
| `SK` | Shared Kernel |
| `P` | Partnership |

**Relationship arrows**:

| Arrow | Meaning |
|-------|---------|
| `A [D] <- [U] B` | B is upstream, A is downstream |
| `A [U] -> [D] B` | A is upstream, B is downstream |
| `A [D,C] <-> [U,S] B` | Customer-Supplier (bidirectional notation) |
| `A <-> B` | Partnership or Shared Kernel |

---

### 13. User Requirements (UseCase / UserStory)

Declared at root level, referenced by Aggregates and Subdomains.

```cml
UseCase CreateCustomer {
  interactions
    create a "Customer" with its "firstname", "lastname",
    update an "Address" for a "Customer"
  benefit "Manage customer data"
}

UserStory UpdateContract {
  As an "Insurance Employee"
    I want to "update" a "Contract" with its "startDate", "endDate"
  so that "contract data is up to date."
}
```

---

## Output Format

### When to Generate .cml Files

Generate `.cml` files when:

- User explicitly asks for a `.cml` file
- User says "create a context mapper model", "generate CML", or similar
- User wants to use the ContextMapper toolchain (generators, visualizations)
- The model is substantial enough to warrant its own file

**File naming**: Use descriptive names like `insurance-domain.cml`, `order-management.cml`, or the domain name in kebab-case.

### When to Generate CML in Markdown

Generate CML blocks inside markdown when:

- User asks for documentation that includes domain models
- User wants to discuss or review a model before committing to a file
- The model is small or illustrative
- User is writing an ADR, TDD, or design doc that includes domain modeling

**Use fenced code blocks** with the `cml` language identifier:

````markdown
```cml
Aggregate Orders {
  Entity Order {
    aggregateRoot
    ...
  }
}
```
````

### When Unsure

Ask the user:

- "Would you like me to generate a `.cml` file or include the CML syntax in a markdown document?"
- "Voce prefere que eu gere um arquivo `.cml` ou inclua a sintaxe CML em um documento markdown?"

---

## Interactive Workflow

### Step 1: Understand the Domain

Before writing any CML, gather domain information from the user:

1. **What is the domain?** -- Ask for a high-level description of the business domain
2. **What are the subdomains?** -- Identify Core, Supporting, and Generic subdomains
3. **What are the bounded contexts?** -- Identify system boundaries and team responsibilities
4. **What are the key domain concepts?** -- Entities, Value Objects, Events, Commands

If the user provides a vague description like "model an e-commerce system", ask clarifying questions:

**English**:
```
To model your domain effectively, I need to understand:

1. **Domain scope**: What is the core business? (e.g., "online retail marketplace")
2. **Key subdomains**: What are the main functional areas? (e.g., ordering, catalog, shipping, payments)
3. **Which subdomains are core** vs. supporting vs. generic?
4. **Key business rules**: What invariants must the system enforce?
5. **Key events**: What important things happen in the domain? (e.g., OrderPlaced, PaymentReceived)

Can you describe these aspects of your domain?
```

**Portuguese**:
```
Para modelar seu dominio de forma eficaz, preciso entender:

1. **Escopo do dominio**: Qual e o negocio principal? (ex: "marketplace de varejo online")
2. **Subdominos principais**: Quais sao as areas funcionais? (ex: pedidos, catalogo, envio, pagamentos)
3. **Quais subdominos sao core** vs. suporte vs. generico?
4. **Regras de negocio chave**: Quais invariantes o sistema deve garantir?
5. **Eventos chave**: O que acontece de importante no dominio? (ex: PedidoRealizado, PagamentoRecebido)

Pode descrever esses aspectos do seu dominio?
```

### Step 2: Model Strategic Elements

Start top-down:

1. Define the `Domain` and its `Subdomain` entries with types and vision statements
2. Define `BoundedContext` entries with `implements` references
3. If relevant, define a `ContextMap` with relationships

Present the strategic model to the user for validation before proceeding to tactical details.

### Step 3: Model Tactical Elements

For each Bounded Context, work aggregate by aggregate:

1. Identify the **Aggregate Root** entity
2. Define **Entities** with their attributes and key references
3. Define **Value Objects** for concepts with no identity
4. Define **Domain Events** for things that happen
5. Define **Commands** for intentions/actions
6. Define **Services** for operations that don't belong to a single entity
7. Define **Repositories** inside aggregate root entities (if needed)
8. Define **Aggregate Lifecycle** enums and state transitions (if applicable)

### Step 4: Review and Iterate

After generating the model:

1. Present a summary of all elements created
2. Ask the user to validate the model
3. Offer refinements: "Would you like to add more aggregates, refine attributes, or define state transitions?"

### Step 5: Validate Before Generating (CRITICAL)

**ALWAYS validate the CML file before attempting diagram generation.**

When working with an existing `.cml` file or after making changes:

```bash
# Step 1: Validate the CML syntax
cm validate -i model.cml

# Step 2: Only if validation passes, generate diagrams
cm generate -i model.cml -o output/ -g context-map
cm generate -i model.cml -o output/ -g plantuml
```

**Common validation errors to watch for:**
- Reserved words used as attributes (`description`, etc.)
- Invalid relationship patterns (`PUBLISHER`, `SUBSCRIBER`)
- Properties outside braces in relationships
- Missing `aggregateRoot` marker
- Duplicate relationships between same contexts

**If validation fails:**
1. Read the error message carefully
2. Check line numbers in the error
3. Refer to "Common Pitfalls and Validation Guide" section
4. Fix issues one at a time
5. Re-validate until clean

---

## Validation Rules

When generating CML, always enforce these rules:

### Naming Rules

- **Aggregate names** must be unique within the entire CML model
- **Bounded Context names** must be unique within the entire CML model
- Type names (Entity, ValueObject, etc.) should be PascalCase
- Attribute names should be camelCase

### Structural Rules

- **Repository** can only be declared inside an Entity marked with `aggregateRoot`
- Each Aggregate should have exactly one Entity marked with `aggregateRoot`
- **`-` references** must point to types that are declared somewhere in the model
- **`@` references** in operations must point to declared types
- **`realizes`** keyword is only valid for Bounded Contexts of `type = TEAM`
- **`implements`** must reference a declared Domain or Subdomain
- Entities inside `Subdomain` blocks are for modeling only -- no Aggregates allowed inside Subdomains
- Service operations and Repository operations do NOT use the `def` keyword
- Entity, ValueObject, and DomainEvent operations DO use the `def` keyword

### Style Rules

- Add CML comments (`/* ... */` or `//`) to explain non-obvious domain decisions
- Group related Aggregates within the same Bounded Context
- Use `domainVisionStatement` to document the purpose of Bounded Contexts and Subdomains
- Prefer explicit `- TypeName` references over implicit untyped attributes when the type is declared in the model
- Use `key` on Value Object attributes that form the identity of the VO

---

## Complete Example

Below is a complete CML model for an e-commerce domain demonstrating all major elements:

```cml
/* ============================================
   E-Commerce Domain Model
   ============================================ */

// ---- Domain & Subdomains ----

Domain ECommerce {
  domainVisionStatement = "Online retail platform connecting buyers and sellers."

  Subdomain OrderManagement {
    type = CORE_DOMAIN
    domainVisionStatement = "Handles the complete order lifecycle from placement to delivery."

    Entity Order {
      String orderId
      String status
    }
  }

  Subdomain CatalogManagement {
    type = SUPPORTING_DOMAIN
    domainVisionStatement = "Manages product catalog, categories, and search."

    Entity Product {
      String name
      String description
    }
  }

  Subdomain ShippingManagement {
    type = GENERIC_SUBDOMAIN
    domainVisionStatement = "Handles shipment tracking and carrier integration."
  }
}

// ---- Bounded Contexts ----

BoundedContext OrderContext implements OrderManagement {
  type = FEATURE
  domainVisionStatement = "Responsible for order placement, payment, and fulfillment."
  implementationTechnology = "Java, Spring Boot"
  responsibilities = "Orders", "Payments"

  Aggregate Orders {
    owner = OrderTeam
    likelihoodForChange = NORMAL
    contentVolatility = OFTEN

    Entity Order {
      aggregateRoot

      - OrderId orderId
      - CustomerId customerId
      - List<OrderLine> lines
      - Money totalPrice
      - ShippingAddress shippingAddress
      OrderStatus status

      def @OrderId place(@List<OrderLine> lines, @ShippingAddress address);
      def void cancel();
      def boolean canBeModified();

      Repository OrderRepository {
        @Order findById(@OrderId orderId);
        List<@Order> findByCustomer(@CustomerId customerId);
        save(@Order order);
      }
    }

    ValueObject OrderId {
      String id key
    }

    ValueObject CustomerId {
      String id key
    }

    ValueObject OrderLine {
      - ProductReference product
      int quantity
      - Money unitPrice
    }

    ValueObject Money {
      BigDecimal amount
      String currency
    }

    ValueObject ShippingAddress {
      String street
      String city
      String postalCode
      String country
    }

    ValueObject ProductReference {
      String productId
      String productName
    }

    DomainEvent OrderPlaced {
      - OrderId orderId
      - CustomerId customerId
      - List<OrderLine> lines
      - Money totalPrice
      Date placedAt
    }

    DomainEvent OrderCancelled {
      - OrderId orderId
      String reason
      Date cancelledAt
    }

    DomainEvent OrderShipped {
      - OrderId orderId
      String trackingNumber
      Date shippedAt
    }

    Command PlaceOrder {
      - CustomerId customerId
      - List<OrderLine> lines
      - ShippingAddress shippingAddress
    }

    Command CancelOrder {
      - OrderId orderId
      String reason
    }

    Service OrderService {
      @OrderId placeOrder(@PlaceOrder command) : write [ -> PLACED];
      void cancelOrder(@CancelOrder command) : write [ PLACED, CONFIRMED -> CANCELLED];
      void confirmOrder(@OrderId orderId) : write [ PLACED -> CONFIRMED];
      void shipOrder(@OrderId orderId) : write [ CONFIRMED -> SHIPPED];
      void deliverOrder(@OrderId orderId) : write [ SHIPPED -> DELIVERED*];
      @Order getOrder(@OrderId orderId) : read-only;
    }

    enum OrderStatus {
      aggregateLifecycle
      PLACED, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
    }
  }
}

BoundedContext CatalogContext implements CatalogManagement {
  type = FEATURE
  domainVisionStatement = "Manages product information, pricing, and availability."
  implementationTechnology = "Kotlin, Spring Boot"

  Aggregate Products {
    Entity Product {
      aggregateRoot

      - ProductId productId
      String name
      String description
      - Money price
      - Category category
      boolean active

      def void activate();
      def void deactivate();
      def void updatePrice(@Money newPrice);

      Repository ProductRepository {
        @Product findById(@ProductId productId);
        List<@Product> findByCategory(@Category category);
        List<@Product> findActive();
        save(@Product product);
      }
    }

    ValueObject ProductId {
      String id key
    }

    ValueObject Money {
      BigDecimal amount
      String currency
    }

    ValueObject Category {
      String code key
      String name
    }

    DomainEvent ProductCreated {
      - ProductId productId
      String name
      - Money price
      Date createdAt
    }

    DomainEvent ProductPriceChanged {
      - ProductId productId
      - Money oldPrice
      - Money newPrice
      Date changedAt
    }

    Service CatalogService {
      @ProductId createProduct(@Product product);
      void updateProduct(@Product product);
      @Product getProduct(@ProductId productId);
      List<@Product> searchProducts(String query);
    }
  }
}

// ---- Teams ----

BoundedContext OrderTeam {
  type = TEAM
}

// ---- Context Map ----

ContextMap ECommerceMap {
  type = SYSTEM_LANDSCAPE
  state = TO_BE

  contains OrderContext, CatalogContext

  // OrderContext consumes product data from CatalogContext
  OrderContext [D,ACL] <- [U,OHS,PL] CatalogContext {
    implementationTechnology = "RESTful HTTP, JSON"
  }
}
```

---

## Common Anti-Patterns to Avoid

### Anemic Aggregates

**BAD** -- Aggregate with no behavior, just data:

```cml
Aggregate Orders {
  Entity Order {
    aggregateRoot
    String status
    - List<OrderLine> lines
    // No operations, no events, no invariants
  }
}
```

**GOOD** -- Aggregate with behavior, events, and lifecycle:

```cml
Aggregate Orders {
  Entity Order {
    aggregateRoot
    - OrderId orderId
    - List<OrderLine> lines
    OrderStatus status

    def @OrderId place(@List<OrderLine> lines);
    def void cancel();
  }

  DomainEvent OrderPlaced { ... }
  DomainEvent OrderCancelled { ... }

  Service OrderService {
    @OrderId placeOrder(@PlaceOrder command) : write [ -> PLACED];
  }

  enum OrderStatus {
    aggregateLifecycle
    PLACED, CONFIRMED, CANCELLED
  }
}
```

### God Aggregate

**BAD** -- One massive Aggregate containing everything:

```cml
Aggregate ECommerce {
  Entity Order { aggregateRoot ... }
  Entity Product { ... }
  Entity Customer { ... }
  Entity Payment { ... }
  Entity Shipment { ... }
  // Too many unrelated concepts in one aggregate
}
```

**GOOD** -- Separate Aggregates per consistency boundary:

```cml
Aggregate Orders {
  Entity Order { aggregateRoot ... }
}
Aggregate Products {
  Entity Product { aggregateRoot ... }
}
Aggregate Customers {
  Entity Customer { aggregateRoot ... }
}
```

### Missing Aggregate Root

**BAD** -- No entity marked as aggregate root:

```cml
Aggregate Orders {
  Entity Order {
    // missing aggregateRoot
    - OrderId orderId
  }
  Entity OrderLine {
    int quantity
  }
}
```

**GOOD** -- Explicit aggregate root:

```cml
Aggregate Orders {
  Entity Order {
    aggregateRoot
    - OrderId orderId
    - List<OrderLine> lines
  }
  Entity OrderLine {
    int quantity
    - Money unitPrice
  }
}
```

### Using `def` in Services (Syntax Error)

**BAD**:

```cml
Service OrderService {
  def @Order getOrder(@OrderId id); // WRONG: def is not used in Services
}
```

**GOOD**:

```cml
Service OrderService {
  @Order getOrder(@OrderId id); // CORRECT: no def in Services
}
```

### Using no `def` in Entities (Syntax Error)

**BAD**:

```cml
Entity Order {
  aggregateRoot
  @OrderId place(@OrderItems items); // WRONG: missing def in Entity
}
```

**GOOD**:

```cml
Entity Order {
  aggregateRoot
  def @OrderId place(@OrderItems items); // CORRECT: def is required in Entities
}
```

---

## Common Pitfalls and Validation Guide

Based on real-world issues encountered when working with CML, here are critical pitfalls to avoid:

### Reserved Words Cannot Be Used as Attribute Names

**CRITICAL**: Some words are reserved in CML and cannot be used as Entity/VO attributes:

| Reserved Word | Where Reserved | Alternative Name |
|---------------|--------------|------------------|
| `description` | Relationship blocks | `desc`, `details`, `info` |
| `implementationTechnology` | Must be inside `{ }` in relationships | N/A - use proper syntax |

**BAD - Using reserved word as attribute:**
```cml
Entity Series {
  String description  // ERROR: description is reserved!
}
```

**GOOD - Use alternative name:**
```cml
Entity Series {
  String seriesDescription  // OK
  String desc               // OK
}
```

### Relationship Properties Require Block Syntax

**CRITICAL**: Properties like `implementationTechnology` in relationships **ONLY** work when using block syntax `{ }`:

**BAD - Properties without braces:**
```cml
ContextMap MyMap {
  UserTrackingContext [D,ACL] <- [U,OHS,PL] SeriesCatalogContext
    implementationTechnology = "RESTful HTTP"  // ERROR: outside braces!
}
```

**GOOD - Properties inside braces:**
```cml
ContextMap MyMap {
  UserTrackingContext [D,ACL] <- [U,OHS,PL] SeriesCatalogContext {
    implementationTechnology = "RESTful HTTP"    // OK: inside braces
  }
}
```

### Valid DDD Relationship Patterns Only

**CRITICAL**: ContextMapper only supports these patterns in relationships:

| Pattern | Abbreviation | Valid In |
|---------|--------------|----------|
| Upstream | `U` | Relationships |
| Downstream | `D` | Relationships |
| Open Host Service | `OHS` | Upstream only |
| Published Language | `PL` | Upstream only |
| Anticorruption Layer | `ACL` | Downstream only |
| Conformist | `CF` | Downstream only |
| Supplier | `S` | Upstream only |
| Customer | `C` | Downstream only |
| Shared Kernel | `SK` | Bidirectional |
| Partnership | `P` | Bidirectional |

**INVALID PATTERNS** (will cause parse errors):
- ~~`PUBLISHER`~~ - Not a valid DDD pattern
- ~~`SUBSCRIBER`~~ - Not a valid DDD pattern
- ~~`PRODUCER`~~ - Not a valid DDD pattern
- ~~`CONSUMER`~~ - Not a valid DDD pattern

**BAD:**
```cml
SeriesCatalogContext [PUBLISHER] -> [SUBSCRIBER] UserTrackingContext  // ERROR!
```

**GOOD:**
```cml
SeriesCatalogContext [U] -> [D] UserTrackingContext  // OK - use U/D for event flows
```

### Always Validate Before Generating

**BEST PRACTICE**: Always run validation before attempting diagram generation:

```bash
# Validate first
cm validate -i model.cml

# Only if validation passes, then generate
cm generate -i model.cml -o output/ -g context-map
```

### Avoid Duplicate Relationships

**WARNING**: Having multiple relationships between the same two Bounded Contexts can confuse the diagram generator:

**PROBLEMATIC:**
```cml
ContextMap MyMap {
  // Two relationships between same contexts - may cause issues
  UserTrackingContext [D,ACL] <- [U,OHS,PL] SeriesCatalogContext
  SeriesCatalogContext [U] -> [D] UserTrackingContext  // Duplicate!
}
```

**BETTER:**
```cml
ContextMap MyMap {
  // Single, complete relationship
  UserTrackingContext [D,ACL] <- [U,OHS,PL] SeriesCatalogContext
}
```

### Context Mapper CLI Installation

If the CLI is not available, download from Maven Central:

```bash
# Download and extract
curl -L -o cm-cli.tar "https://repo1.maven.org/maven2/org/contextmapper/context-mapper-cli/6.12.0/context-mapper-cli-6.12.0.tar"
tar -xf cm-cli.tar

# Use the CLI
./context-mapper-cli-6.12.0/bin/cm validate -i model.cml
./context-mapper-cli-6.12.0/bin/cm generate -i model.cml -o output/ -g context-map
```

### Understanding CML Errors

Common error messages and their meaning:

| Error Message | Meaning | Solution |
|---------------|---------|----------|
| `mismatched input 'X' expecting RULE_ID` | Used reserved word as identifier | Rename the identifier |
| `no viable alternative at input 'Y'` | Invalid syntax or unknown keyword | Check spelling and valid patterns |
| `mismatched input 'description' expecting RULE_CLOSE` | Used `description` property outside braces | Move inside `{ }` or remove |

---

## Quick Syntax Cheat Sheet

| Element | Keyword | Inside | Uses `def`? | Uses `-` refs? | Uses `@` refs? |
|---------|---------|--------|-------------|----------------|-----------------|
| Domain | `Domain` | root | N/A | N/A | N/A |
| Subdomain | `Subdomain` | Domain | N/A | N/A | N/A |
| Bounded Context | `BoundedContext` | root | N/A | N/A | N/A |
| Aggregate | `Aggregate` | BoundedContext | N/A | N/A | N/A |
| Entity | `Entity` | Aggregate | Yes | Yes | Yes (in methods) |
| Value Object | `ValueObject` | Aggregate | Yes | Yes | Yes (in methods) |
| Domain Event | `DomainEvent` / `Event` | Aggregate | Yes | Yes | Yes (in methods) |
| Command | `Command` / `CommandEvent` | Aggregate | Yes | Yes | Yes (in methods) |
| Service | `Service` | Aggregate or BC | **No** | No | Yes |
| Repository | `Repository` | aggregate root Entity only | **No** | No | Yes |

---

## Example Prompts that Trigger This Skill

### English

- "Model the domain for an e-commerce platform"
- "Create bounded contexts for a hospital management system"
- "Design the aggregates for an order management system"
- "Write a CML model for a logistics domain"
- "Help me define the domain events for a banking system"
- "Create a context mapper model"

### Portuguese

- "Modele o dominio de uma plataforma de e-commerce"
- "Crie bounded contexts para um sistema de gestao hospitalar"
- "Projete os agregados para um sistema de pedidos"
- "Escreva um modelo CML para um dominio de logistica"
- "Me ajude a definir os domain events de um sistema bancario"
- "Crie um modelo context mapper"
