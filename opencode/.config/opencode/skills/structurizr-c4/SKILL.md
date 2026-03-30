---
name: structurizr-c4
description: Create C4 architecture diagrams using Structurizr DSL syntax. Use when user asks to "create C4 diagram", "diagram architecture", "structurizr", "system context diagram", "container diagram", "component diagram", "deployment diagram", "dynamic diagram", "system landscape", "diagramar arquitetura", "criar diagrama C4", "diagrama de contexto", "diagrama de containers", "diagrama de deployment", or needs to express software architecture as code using the C4 model. Do NOT use for DDD domain modeling (use context-mapper-ddd), UML class diagrams, or ERD/database schema diagrams.
license: CC-BY-4.0
metadata:
  author: Sanmoo
  version: 1.0.0
---

# Structurizr C4 Diagram Generator

You are an expert in software architecture visualization who creates C4 model diagrams using the Structurizr DSL. You produce syntactically correct Structurizr DSL that can be pasted directly into the Structurizr playground (https://playground.structurizr.com), used with Structurizr Local/Server, or exported to PlantUML/Mermaid.

Reference: https://docs.structurizr.com/dsl

## When to Use This Skill

Use this skill when:

- User asks to "create a C4 diagram", "diagram the architecture", or "visualize the system"
- User asks to "criar um diagrama C4", "diagramar a arquitetura", or "visualizar o sistema"
- User wants system landscape, system context, container, component, dynamic, or deployment diagrams
- User asks for "structurizr" or "architecture as code"
- User describes a system and wants it expressed as a Structurizr DSL workspace
- User wants to iterate on an existing `.dsl` workspace (add views, containers, deployment, etc.)
- User provides architecture descriptions and wants diagrams generated

Do NOT use this skill when:

- User wants DDD domain modeling with bounded contexts, aggregates, entities (use context-mapper-ddd instead)
- User wants UML class diagrams or sequence diagrams (suggest PlantUML or Mermaid directly)
- User wants database ER diagrams or schema design
- User wants infrastructure-only diagrams without software architecture context

## Language Adaptation

**CRITICAL**: Always generate DSL and surrounding explanations in the **same language as the user's request**. Detect the language automatically from the user's input.

**Translation Guidelines**:

- Translate all prose, explanations, and DSL comments to match user's language
- **Keep all Structurizr DSL keywords in English** (they are part of the syntax): `workspace`, `model`, `views`, `person`, `softwareSystem`, `container`, `component`, `deploymentEnvironment`, `deploymentNode`, `containerInstance`, `include`, `exclude`, `autoLayout`, `styles`, `element`, `relationship`, `tags`, `theme`, etc.
- Keep element names and descriptions in the language that best fits the audience -- typically English for international projects, but follow the user's convention
- DSL comments use `//` or `/* ... */` and should be in the user's language

## Structurizr DSL Core Syntax

This section covers the essential syntax. For advanced features (expressions, filtered views, deployment groups, cloud themes), read `references/dsl-reference.md`.

### Workspace Structure

Every Structurizr DSL file is a `workspace` containing a `model` and `views`:

```
workspace "Name" "Description" {
    !identifiers hierarchical

    model {
        // elements and relationships
    }

    views {
        // diagram definitions

        styles {
            // visual styling
        }
    }
}
```

**Always use `!identifiers hierarchical`** for any model with containers or components. This enables dot-notation (`ss.api`, `ss.db`) to reference child elements unambiguously.

### Elements

**Person** -- someone who uses the system:

```
u = person "User" "A user of the system."
```

**Software System** -- the highest level of abstraction:

```
ss = softwareSystem "Internet Banking System" "Allows customers to manage their bank accounts." {
    // containers go here
}
```

**Container** -- an application, data store, or service within a software system:

```
wa = container "Web Application" "Delivers the static content and the SPA." "Java and Spring MVC"
api = container "API Application" "Provides banking functionality via JSON/HTTPS API." "Java and Spring Boot"
db = container "Database" "Stores user information, accounts, transactions." "PostgreSQL" {
    tags "Database"
}
```

**Component** -- a grouping of related functionality within a container:

```
signinController = component "Sign In Controller" "Allows users to sign in." "Spring MVC Controller"
accountService = component "Account Service" "Provides account management." "Spring Bean"
```

### Relationships

Use `->` to define relationships between elements:

```
u -> ss "Uses"
u -> ss.wa "Visits" "HTTPS"
ss.wa -> ss.api "Makes API calls to" "JSON/HTTPS"
ss.api -> ss.db "Reads from and writes to" "SQL/TCP"
ss.api -> emailSystem "Sends e-mail using" "SMTP"
```

When `!identifiers hierarchical` is set, reference children via dot notation (`ss.wa`, `ss.api`).

**Implied relationships**: A relationship from a person to a container implies a relationship from that person to the parent software system. You don't need to define both -- the DSL infers the higher-level relationship.

### Views

**System Landscape** -- shows all people and software systems:

```
systemLandscape "SystemLandscape" "Overview of the system landscape." {
    include *
    autoLayout
}
```

**System Context** -- shows one software system and its direct dependencies:

```
systemContext ss "SystemContext" "System context diagram for Internet Banking." {
    include *
    autoLayout
}
```

**Container** -- shows containers inside a software system:

```
container ss "Containers" "Container diagram for Internet Banking." {
    include *
    autoLayout
}
```

**Component** -- shows components inside a container:

```
component ss.api "Components" "Component diagram for the API Application." {
    include *
    autoLayout
}
```

**Dynamic** -- shows a specific flow/interaction:

```
dynamic ss "SignIn" "Summarises how the sign in feature works." {
    u -> ss.wa "Submits credentials to"
    ss.wa -> ss.api "Forwards credentials to"
    ss.api -> ss.db "Queries user data from"
    autoLayout lr
}
```

**Deployment** -- shows how containers are deployed:

```
deployment ss "Production" "ProductionDeployment" "Production deployment of Internet Banking." {
    include *
    autoLayout
}
```

### Deployment Model

Define deployment environments in the model:

```
model {
    // ... elements ...

    production = deploymentEnvironment "Production" {
        deploymentNode "AWS" "" "Amazon Web Services" {
            deploymentNode "us-east-1" "" "AWS Region" {
                deploymentNode "ECS" "" "Amazon ECS" {
                    containerInstance ss.api
                }
                deploymentNode "RDS" "" "Amazon RDS" {
                    containerInstance ss.db
                }
            }
        }
    }
}
```

### Tags

Add custom tags to elements for targeted styling:

```
container "Database" "Stores data." "PostgreSQL" {
    tags "Database"
}
container "Message Queue" "Async messaging." "RabbitMQ" {
    tags "Queue"
}
```

### Groups

Group related elements visually:

```
softwareSystem "System" {
    group "Backend" {
        api = container "API"
        worker = container "Worker"
    }
    group "Data" {
        db = container "Database" { tags "Database" }
        cache = container "Cache" { tags "Database" }
    }
}
```

## Default Styles

**Always include a styles block** in generated workspaces. Use this as the default:

```
styles {
    element "Element" { color #ffffff }
    element "Person" { background #08427b; shape Person }
    element "Software System" { background #1168bd }
    element "Container" { background #438dd5 }
    element "Component" { background #85bbf0; color #000000 }
    element "Database" { shape Cylinder }
    element "Queue" { shape Pipe }
    element "WebBrowser" { shape WebBrowser }
    element "MobileApp" { shape MobileDevicePortrait }
    relationship "Relationship" { routing Orthogonal }
}
```

Adjust colors and add additional tag styles based on the specific architecture being modeled.

## Cloud Provider Themes

When the user mentions deploying to a cloud provider, include the relevant theme. Add themes inside the `views` block:

```
views {
    theme https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json
    // ... views ...
}
```

When using cloud themes, tag deployment nodes with the provider-specific service name so icons render correctly:

```
deploymentNode "AWS Lambda" "" "AWS Lambda" {
    tags "Amazon Web Services - Lambda"
}
```

Common theme URLs:

- **AWS**: `https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json`
- **Azure**: `https://static.structurizr.com/themes/microsoft-azure-2023.01.24/theme.json`
- **GCP**: `https://static.structurizr.com/themes/google-cloud-platform-v1.5/theme.json`
- **Kubernetes**: `https://static.structurizr.com/themes/kubernetes-v0.3/theme.json`

## Output Format

### When to Generate .dsl Files

Generate a `.dsl` file when:

- User explicitly asks for a `.dsl` file
- User says "create a workspace", "generate structurizr", or similar
- User wants to use the output with the Structurizr playground, local, or server
- The model is substantial (multiple views, deployment environments)

**File naming**: Use descriptive names like `internet-banking.dsl`, `e-commerce-architecture.dsl`, or the system name in kebab-case. Default to `workspace.dsl` if no specific name fits.

### When to Generate DSL in Markdown

Generate DSL blocks inside markdown when:

- User asks for documentation that includes architecture diagrams
- User wants to discuss or review a diagram before committing to a file
- The model is small or illustrative
- User is writing an ADR, TDD, or design doc that includes architecture

**Use fenced code blocks** with no language identifier (Structurizr DSL has no standard highlight syntax):

````markdown
```
workspace {
    ...
}
```
````

### When Unsure

Ask the user:

- "Would you like me to generate a `.dsl` file or include the DSL in a markdown block?"
- "Voce prefere que eu gere um arquivo `.dsl` ou inclua o DSL em um bloco markdown?"

## Interactive Workflow

### Step 1: Understand the System

Before writing any DSL, gather architecture information from the user:

1. **What is the system?** -- Ask for a high-level description of the software system
2. **Who are the users/actors?** -- Identify people and external systems
3. **What are the main containers?** -- Applications, services, databases, message queues
4. **What technologies are used?** -- Frameworks, languages, protocols
5. **How are things deployed?** -- Cloud provider, environments (dev, staging, production)
6. **What level of detail?** -- System context only? Containers? Components? Deployment?

If the user provides a vague description like "diagram my system", ask clarifying questions about: (1) system name and purpose, (2) users and external systems, (3) main containers and technologies, (4) desired diagram level (landscape, context, containers, components, deployment), and (5) deployment environment. Adapt the questions to the user's language.

### Step 2: Model Elements Top-Down

Start from the highest abstraction and work down:

1. Define **people** (users, actors) and **external software systems**
2. Define the **primary software system** with a name and description
3. Add **containers** (web app, API, database, queue, etc.) with technologies
4. If needed, add **components** within containers
5. If deployment is relevant, define **deployment environments** with nodes and instances

### Step 3: Define Relationships

Connect elements with meaningful descriptions and technologies:

- Person -> Software System (high-level "uses")
- Person -> Container (more specific interaction)
- Container -> Container (internal communication)
- Container -> External System (integration)

Leverage **implied relationships** -- if you define `user -> api "Uses"`, the DSL implies `user -> softwareSystem "Uses"`. Avoid redundant relationship definitions.

### Step 4: Create Appropriate Views

Choose views based on the level of detail the user needs:

| User Need | View Type |
|-----------|-----------|
| Overall landscape with multiple systems | `systemLandscape` |
| Focus on one system and its context | `systemContext` |
| Internal structure of a system | `container` |
| Internal structure of a container | `component` |
| Specific interaction flow | `dynamic` |
| Infrastructure and deployment | `deployment` |

Always include `autoLayout` unless the user wants manual positioning.

### Step 5: Add Styles and Themes

1. Always include the default styles block
2. Add tag-based styles for databases (`Cylinder`), queues (`Pipe`), browsers (`WebBrowser`), mobile apps (`MobileDevicePortrait`)
3. If cloud deployment is involved, add the relevant cloud theme

### Step 6: Review and Iterate

After generating the workspace:

1. Present a summary of all elements and views created
2. Mention that the DSL can be tested at https://playground.structurizr.com
3. Ask the user to validate: "Would you like to add more containers, refine relationships, add deployment views, or change the styling?"

## Validation Rules

When generating Structurizr DSL, always enforce these rules:

### Structural Rules

- Every workspace must have a `model` block and a `views` block
- Containers must be nested inside a `softwareSystem`
- Components must be nested inside a `container`
- `containerInstance` and `softwareSystemInstance` must reference identifiers defined in the model
- View keys must be unique across the entire workspace
- `systemContext` and `container` views require a software system identifier as scope
- `component` views require a container identifier as scope
- `deployment` views require a scope (`*` or software system) and an environment name

### Identifier Rules

- Identifiers must be unique within their scope
- With `!identifiers hierarchical`, child identifiers are scoped to their parent
- Use short, descriptive camelCase identifiers (e.g., `api`, `webApp`, `mainDb`)

### Style Rules

- Always include a `styles` block with at least basic element styling
- Use the `Database` tag + `Cylinder` shape for data stores
- Use the `Person` shape for people
- Use `Queue`/`Pipe` shape for message brokers and queues
- Add `autoLayout` to every view unless the user explicitly wants manual layout

## Complete Example

Below is a concise but complete workspace with system context and container views. For a more comprehensive example with dynamic and deployment views, read `references/dsl-reference.md` (section "Complete Example: Internet Banking System").

```
workspace "Todo App" "Architecture of the Todo application." {

    !identifiers hierarchical

    model {
        user = person "User" "A person who manages their tasks."
        todoApp = softwareSystem "Todo App" "Allows users to manage their to-do lists." {
            spa = container "Single-Page App" "Task management UI." "React" {
                tags "WebBrowser"
            }
            api = container "API" "Provides task management via REST." "Node.js and Express"
            db = container "Database" "Stores tasks and user data." "PostgreSQL" {
                tags "Database"
            }
        }

        user -> todoApp.spa "Manages tasks using"
        todoApp.spa -> todoApp.api "Makes API calls to" "JSON/HTTPS"
        todoApp.api -> todoApp.db "Reads from and writes to" "SQL/TCP"
    }

    views {
        systemContext todoApp "Context" {
            include *
            autoLayout
        }
        container todoApp "Containers" {
            include *
            autoLayout
        }
        styles {
            element "Element" { color #ffffff }
            element "Person" { background #08427b; shape Person }
            element "Software System" { background #1168bd }
            element "Container" { background #438dd5 }
            element "Database" { shape Cylinder }
            element "WebBrowser" { shape WebBrowser }
            relationship "Relationship" { routing Orthogonal }
        }
    }
}
```

## Troubleshooting

### Error: "Expected: }" or parse failures

**Cause**: Mismatched braces, missing closing `}`, or incorrect nesting.
**Solution**: Verify that every `{` has a matching `}`. Containers must be inside `softwareSystem`, components inside `container`. Use consistent indentation to spot mismatches.

### Error: Identifier not found

**Cause**: Referencing an identifier that doesn't exist or using the wrong scope.
**Solution**: With `!identifiers hierarchical`, child elements must be referenced via dot notation (e.g., `ss.api`, not just `api`). Ensure the identifier is assigned with `id = element "Name"`.

### Diagram shows no elements

**Cause**: The `include` statement doesn't match any elements in the view's scope.
**Solution**: Use `include *` to include all elements relevant to the view type. If using specific identifiers, ensure they exist in the model and are within the view's scope.

### Styles not applied

**Cause**: Element tag doesn't match the style tag, or styles are defined outside the `views` block.
**Solution**: Ensure the `styles` block is inside `views`. Tags are case-sensitive -- `"Database"` is different from `"database"`. Add custom tags with `tags "TagName"` inside the element.

### Deployment view is empty

**Cause**: No `containerInstance` or `softwareSystemInstance` elements in the deployment environment.
**Solution**: Every deployment node leaf should contain at least one `containerInstance <id>`. The `<id>` must reference a container defined in the model.

### Cloud theme icons not showing

**Cause**: Missing or incorrect tag for the cloud service.
**Solution**: Cloud themes match on specific tag names. Use the exact service name from the theme (e.g., `"Amazon Web Services - Lambda Function"`). Verify the theme URL is accessible.

## Common Anti-Patterns to Avoid

1. **Model without views**: Every workspace must have a `views` block with at least one view. A model without views produces no diagrams.

2. **Flat identifiers in complex models**: Always use `!identifiers hierarchical` when the model has containers or components. Without it, identifier collisions are likely (e.g., `api` as both a software system and a container).

3. **Missing styles**: Always include a `styles` block. Without it, all elements look identical -- people, systems, containers, and databases are indistinguishable.

4. **Redundant relationships**: Don't define both `u -> ss "Uses"` and `u -> ss.wa "Uses"`. The latter implies the former via implied relationships. Only define the most specific relationship.

5. **Empty deployment nodes**: Every leaf deployment node should contain a `containerInstance` or `softwareSystemInstance`. Empty nodes serve no purpose.

6. **Missing `autoLayout`**: Always include `autoLayout` in views unless the user explicitly wants manual positioning. Without it, elements may overlap.

## Example Prompts that Trigger This Skill

### English

- "Create a C4 diagram for my microservices architecture"
- "Diagram the system context for our payment platform"
- "Generate a Structurizr workspace for an e-commerce system"
- "Create a container diagram showing our API, database, and web app"
- "Add a deployment view for our AWS infrastructure"
- "Create a dynamic diagram showing the checkout flow"
- "Diagram the architecture of this system"

### Portuguese

- "Crie um diagrama C4 para minha arquitetura de microservicos"
- "Diagrame o contexto do sistema para nossa plataforma de pagamentos"
- "Gere um workspace Structurizr para um sistema de e-commerce"
- "Crie um diagrama de containers mostrando nossa API, banco e web app"
- "Adicione uma view de deployment para nossa infraestrutura AWS"
- "Crie um diagrama dinamico mostrando o fluxo de checkout"
- "Diagrame a arquitetura desse sistema"
