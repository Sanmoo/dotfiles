# Structurizr DSL Language Reference

This is a condensed reference for the Structurizr DSL. Consult this file when you need syntax details for specific keywords, advanced features (expressions, deployment groups, filtered views), or cloud provider themes.

Full documentation: https://docs.structurizr.com/dsl/language

## Workspace Structure

```
workspace [name] [description] {
    !identifiers hierarchical    // recommended for complex models

    model {
        // elements and relationships
    }

    views {
        // diagram definitions
        styles {
            // element and relationship styles
        }
    }
}
```

## Model Elements

| Keyword | Syntax | Default Tags |
|---------|--------|-------------|
| `person` | `person <name> [description] [tags]` | `Element`, `Person` |
| `softwareSystem` | `softwareSystem <name> [description] [tags]` | `Element`, `Software System` |
| `container` | `container <name> [description] [technology] [tags]` | `Element`, `Container` |
| `component` | `component <name> [description] [technology] [tags]` | `Element`, `Component` |
| `element` | `element <name> [metadata] [description] [tags]` | `Element` (custom element) |

### Nesting Rules

- `person` and `softwareSystem` are defined at the `model` level
- `container` is defined inside a `softwareSystem`
- `component` is defined inside a `container`

### Identifier Assignment

```
identifier = person "Name" "Description"
identifier = softwareSystem "Name" {
    childId = container "Name" "Description" "Technology"
}
```

### Hierarchical Identifiers

When `!identifiers hierarchical` is set, child elements are referenced via dot notation:

```
ss = softwareSystem "System" {
    api = container "API"
}
// Reference: ss.api
```

## Relationships

```
// Explicit source
<sourceId> -> <destId> [description] [technology] [tags]

// Inline (inside element block)
-> <destId> [description] [technology] [tags]
```

Default tag: `Relationship`

### Allowed Relationship Endpoints

Source: Person, Software System, Container, Component
Destination: Person, Software System, Container, Component

Deployment-level: Deployment Node -> Deployment Node, Infrastructure Node -> various instances

## Deployment Model

```
deploymentEnvironment <name> {
    deploymentNode <name> [description] [technology] [tags] [instances] {
        deploymentNode <name> {  // can be nested
            infrastructureNode <name> [description] [technology] [tags]
            containerInstance <identifier> [deploymentGroups] [tags]
            softwareSystemInstance <identifier> [deploymentGroups] [tags]
        }
    }
}
```

### Instances

```
instances "4"       // static number
instances "1..N"    // range
instances "0..*"    // range with wildcard
```

## Views

| View Type | Syntax | Scope |
|-----------|--------|-------|
| System Landscape | `systemLandscape [key] [description]` | All people and software systems |
| System Context | `systemContext <ssId> [key] [description]` | Software system + direct dependencies |
| Container | `container <ssId> [key] [description]` | Containers inside software system + external dependencies |
| Component | `component <containerId> [key] [description]` | Components inside container + external dependencies |
| Dynamic | `dynamic <*\|ssId\|containerId> [key] [description]` | Varies by scope |
| Deployment | `deployment <*\|ssId> <environment> [key] [description]` | Deployment nodes + instances for the environment |
| Filtered | `filtered <baseKey> <include\|exclude> <tags> [key] [description]` | Filter elements/relationships from a base view |
| Custom | `custom [key] [title] [description]` | Custom elements only |

### Include / Exclude

```
// Include wildcard (all relevant elements for the view type)
include *

// Include specific elements
include identifier1 identifier2

// Include via expressions
include "->element.type==container->"    // all containers + dependencies
include "->ss.api->"                     // element + inbound/outbound deps
include "element.parent==ss"             // children of ss

// Exclude
exclude identifier1
exclude "identifier1 -> identifier2"     // exclude specific relationship
exclude "* -> *"                         // exclude all relationships
```

### Auto Layout

```
autoLayout [direction] [rankSeparation] [nodeSeparation]
```

| Direction | Meaning |
|-----------|---------|
| `tb` | Top to bottom (default) |
| `bt` | Bottom to top |
| `lr` | Left to right |
| `rl` | Right to left |

Default separations: 300px each.

### Dynamic View Relationships

```
dynamic <scope> [key] [description] {
    sourceId -> destId "Step description" "Technology"
    // or with explicit ordering:
    1: sourceId -> destId "First step"
    2: destId -> anotherId "Second step"
}
```

### Animation

```
animation {
    identifier1 identifier2    // step 1
    identifier3                // step 2
}
```

## Styles

### Element Styles

```
element <tag> {
    shape <Shape>
    icon <file|url>
    width <integer>
    height <integer>
    background <#rrggbb|colorName>
    color <#rrggbb|colorName>         // foreground/text color
    stroke <#rrggbb|colorName>
    strokeWidth <integer: 1-10>
    fontSize <integer>
    border <solid|dashed|dotted>
    opacity <integer: 0-100>
    metadata <true|false>
    description <true|false>
}
```

### Available Shapes

| Shape | Use For |
|-------|---------|
| `Box` | Default |
| `RoundedBox` | General purpose |
| `Circle` | |
| `Ellipse` | |
| `Hexagon` | |
| `Diamond` | Decision points |
| `Cylinder` | Databases |
| `Bucket` | Storage |
| `Pipe` | Queues/messaging |
| `Person` | People |
| `Robot` | Automated actors |
| `Folder` | File systems |
| `WebBrowser` | Web applications |
| `Window` | Desktop applications |
| `Terminal` / `Shell` | CLI tools |
| `MobileDevicePortrait` / `MobileDeviceLandscape` | Mobile apps |
| `Component` | Components |

### Relationship Styles

```
relationship <tag> {
    thickness <integer>
    color <#rrggbb|colorName>
    style <solid|dashed|dotted>
    routing <Direct|Orthogonal|Curved>
    fontSize <integer>
    width <integer>
    position <integer: 0-100>
    opacity <integer: 0-100>
}
```

### Light / Dark Mode

```
styles {
    light {
        element "Element" { ... }
    }
    dark {
        element "Element" { ... }
    }
}
```

## Tags

```
// Add tags to elements
softwareSystem "System" {
    tags "Tag1" "Tag2"
    // or
    tags "Tag1,Tag2"
}

// Add custom tags to containers
container "Database" {
    tags "Database"
}
```

Tags are inherited and cumulative. Style elements by targeting their tags.

## Groups

```
group "Group Name" {
    // elements of the same type
}
```

Groups render as boundary boxes. Can be nested. Only group elements of the same abstraction level.

## Cloud Provider Themes

Use the `theme` or `themes` keyword inside the `views` block to apply cloud provider icon themes:

```
views {
    theme https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json
    // or multiple:
    themes https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json https://static.structurizr.com/themes/kubernetes-v0.3/theme.json
}
```

### Common Theme URLs

| Provider | URL |
|----------|-----|
| Amazon Web Services | `https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json` |
| Microsoft Azure | `https://static.structurizr.com/themes/microsoft-azure-2023.01.24/theme.json` |
| Google Cloud Platform | `https://static.structurizr.com/themes/google-cloud-platform-v1.5/theme.json` |
| Oracle Cloud Infrastructure | `https://static.structurizr.com/themes/oracle-cloud-infrastructure-2021.04.30/theme.json` |
| Kubernetes | `https://static.structurizr.com/themes/kubernetes-v0.3/theme.json` |

When using cloud themes, tag deployment nodes or infrastructure nodes with the service name (e.g., `"Amazon Web Services - Lambda Function"`) so the theme icons are applied.

## Properties and Perspectives

```
properties {
    "key" "value"
}

perspectives {
    "Security" "Description of security perspective" "value"
}
```

## Terminology Override

```
terminology {
    person "Actor"
    softwareSystem "Application"
    container "Service"
    component "Module"
    deploymentNode "Server"
    relationship "Dependency"
}
```

## Workspace Extension

```
workspace extends <file|url> {
    model {
        // add more elements/relationships
    }
    views {
        // add more views
    }
}
```

## Useful Inline Directives

| Directive | Purpose |
|-----------|---------|
| `!identifiers hierarchical` | Enable dot-notation for child elements |
| `!include <file>` | Include another DSL file |
| `!docs <directory>` | Include markdown documentation |
| `!adrs <directory>` | Include ADR files |

## Common Expression Patterns

### Element Expressions

| Expression | Meaning |
|------------|---------|
| `element.type==softwareSystem` | All software systems |
| `element.type==container` | All containers |
| `element.type==component` | All components |
| `element.parent==<id>` | Children of element |
| `element.tag==<tag>` | Elements with specific tag |

### Relationship Expressions (for include/exclude)

| Expression | Meaning |
|------------|---------|
| `* -> *` | All relationships |
| `<id> -> *` | All relationships from element |
| `* -> <id>` | All relationships to element |
| `<id> -> <id>` | Specific relationship |
| `->element.type==container->` | Inbound/outbound of all containers |

## Configuration

```
configuration {
    scope <landscape|softwaresystem|none>
    visibility <public|private>
    users {
        <username> <read|write>
    }
}
```

## Complete Example: Internet Banking System

A full Structurizr DSL workspace demonstrating system context, container, dynamic, and deployment views:

```
workspace "Internet Banking System" "Architecture of the Internet Banking System." {

    !identifiers hierarchical

    model {
        // People
        customer = person "Personal Banking Customer" "A customer of the bank, with personal bank accounts."

        // External Systems
        mainframe = softwareSystem "Mainframe Banking System" "Stores all core banking information." {
            tags "External"
        }
        emailSystem = softwareSystem "E-mail System" "The internal e-mail system." {
            tags "External"
        }

        // Primary System
        ibs = softwareSystem "Internet Banking System" "Allows customers to view and manage their bank accounts online." {

            webApp = container "Web Application" "Delivers the single-page application." "Java and Spring MVC"
            spa = container "Single-Page Application" "Provides banking functionality to customers via their web browser." "JavaScript and React" {
                tags "WebBrowser"
            }
            mobileApp = container "Mobile App" "Provides banking functionality to customers via their mobile device." "React Native" {
                tags "MobileApp"
            }
            api = container "API Application" "Provides Internet banking functionality via a JSON/HTTPS API." "Java and Spring Boot"
            db = container "Database" "Stores user registration, authentication, and access logs." "PostgreSQL" {
                tags "Database"
            }
        }

        // Relationships
        customer -> ibs.spa "Views account balances and makes payments using"
        customer -> ibs.mobileApp "Views account balances and makes payments using"
        ibs.webApp -> ibs.spa "Delivers to the customer's web browser"
        ibs.spa -> ibs.api "Makes API calls to" "JSON/HTTPS"
        ibs.mobileApp -> ibs.api "Makes API calls to" "JSON/HTTPS"
        ibs.api -> ibs.db "Reads from and writes to" "SQL/TCP"
        ibs.api -> mainframe "Gets account information from" "XML/HTTPS"
        ibs.api -> emailSystem "Sends e-mail using" "SMTP"

        // Deployment
        production = deploymentEnvironment "Production" {
            deploymentNode "Customer's Device" "" "Web Browser or Mobile" {
                deploymentNode "Web Browser" "" "Chrome, Firefox, Safari" {
                    containerInstance ibs.spa
                }
                deploymentNode "Mobile Device" "" "iOS or Android" {
                    containerInstance ibs.mobileApp
                }
            }
            deploymentNode "AWS" "" "Amazon Web Services" {
                deploymentNode "us-east-1" "" "AWS Region" {
                    deploymentNode "ECS Cluster" "" "Amazon ECS" {
                        deploymentNode "Web Server" "" "Amazon ECS Service" {
                            containerInstance ibs.webApp
                        }
                        deploymentNode "API Server" "" "Amazon ECS Service" instances "2" {
                            containerInstance ibs.api
                        }
                    }
                    deploymentNode "RDS" "" "Amazon RDS" {
                        containerInstance ibs.db
                    }
                }
            }
        }
    }

    views {
        // System Context
        systemContext ibs "SystemContext" "System context diagram for the Internet Banking System." {
            include *
            autoLayout
        }

        // Container
        container ibs "Containers" "Container diagram for the Internet Banking System." {
            include *
            autoLayout
        }

        // Dynamic: Sign-in flow
        dynamic ibs "SignIn" "Summarises how the sign in feature works." {
            customer -> ibs.spa "Enters credentials into"
            ibs.spa -> ibs.api "Submits credentials to" "JSON/HTTPS"
            ibs.api -> ibs.db "Validates credentials against" "SQL/TCP"
            autoLayout lr
        }

        // Deployment
        deployment ibs "Production" "ProductionDeployment" "Production deployment of Internet Banking." {
            include *
            autoLayout
        }

        // Styles
        styles {
            element "Element" {
                color #ffffff
            }
            element "Person" {
                background #08427b
                shape Person
            }
            element "Software System" {
                background #1168bd
            }
            element "External" {
                background #999999
            }
            element "Container" {
                background #438dd5
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
            element "Database" {
                shape Cylinder
            }
            element "WebBrowser" {
                shape WebBrowser
            }
            element "MobileApp" {
                shape MobileDevicePortrait
            }
            relationship "Relationship" {
                routing Orthogonal
            }
        }
    }
}
```
