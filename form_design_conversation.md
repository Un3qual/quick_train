The cleanest approach is to separate **question/field type** from **answer storage type**. That avoids both extremes: a giant JSON blob and dozens of nearly identical answer tables.

A radio group, dropdown, Tinder-style A/B choice, and image choice may be different UI/question types, but structurally they all produce a **single selected option**.

## 1. Normalize around the value model, not every UI widget

For example:

| Field type           | Stored answer shape    |
| -------------------- | ---------------------- |
| Short text           | text                   |
| Long text            | text                   |
| Code editor          | text                   |
| Integer rating       | integer                |
| Slider               | number                 |
| Yes/no               | boolean                |
| Radio                | single option          |
| Dropdown             | single option          |
| A/B preference       | single option          |
| Checkboxes           | multiple options       |
| Ranking              | ordered options        |
| Image classification | single/multiple option |
| Bounding box         | geometry/annotation    |
| Segmentation         | geometry/mask          |

So I would have something conceptually like:

```text
Field
├── renderer/type: "radio", "dropdown", "pairwise", "rating", ...
└── value_type: TEXT | INTEGER | DECIMAL | BOOLEAN |
                SINGLE_OPTION | MULTI_OPTION | RANKING | ...
```

That distinction is the part that makes the schema manageable.

---

# Core normalized schema

### `forms`

```sql
forms
-----
id
name
```

### `form_versions`

```sql
form_versions
-------------
id
form_id
version
created_at
```

Forms should be versioned because changing a field after receiving responses otherwise creates historical ambiguity.

### `fields`

```sql
fields
------
id
form_version_id
key
type
position
required
label
description
```

Example:

```text
id:       123
key:      preferred_response
type:     pairwise_choice
required: true
```

I would generally let your application code know that `pairwise_choice` produces a `SINGLE_OPTION` answer rather than storing redundant `value_type` if the mapping is fixed.

---

# Field-specific configuration

This is where **supertype/subtype tables** work very well.

The common stuff stays in `fields`, while properties that only apply to one family go elsewhere.

For example:

```sql
text_field_config
-----------------
field_id PK/FK
min_length
max_length
multiline
```

```sql
numeric_field_config
--------------------
field_id PK/FK
minimum
maximum
step
```

```sql
choice_field_config
-------------------
field_id PK/FK
randomize_options
allow_other
```

Then options:

```sql
field_options
-------------
id
field_id
key
label
position
```

For:

> Which response is better?

you might have:

```text
fields

123 | preferred_response | pairwise_choice
```

and:

```text
field_options

901 | 123 | response_a | Response A | 0
902 | 123 | response_b | Response B | 1
903 | 123 | tie        | Tie        | 2
```

That is much better than stuffing:

```json
{
  "options": [...]
}
```

into the field if options are meaningful database entities.

---

# Submissions

```sql
submissions
-----------
id
form_version_id
worker_id
submitted_at
```

Then:

```sql
answers
-------
id
submission_id
field_id
```

`answers` represents:

> This submission provided an answer for this field.

But it does **not necessarily contain the value itself**.

Then normalize values according to their fundamental type.

---

# Typed answer tables

For scalar values:

```sql
text_answers
------------
answer_id PK/FK
value text
```

```sql
integer_answers
---------------
answer_id PK/FK
value bigint
```

```sql
decimal_answers
---------------
answer_id PK/FK
value numeric
```

```sql
boolean_answers
---------------
answer_id PK/FK
value boolean
```

And choice answers are relational:

```sql
selected_options
----------------
answer_id
option_id

PRIMARY KEY (answer_id, option_id)
```

This works for both single-select and multi-select.

A single-choice field simply has a constraint that only one `selected_options` row may exist for that answer.

For a checkbox question:

```text
answer 1001
  → option A
  → option C
  → option D
```

instead of:

```json
["a", "c", "d"]
```

That's quite nicely normalized.

---

# Ranking is slightly different

For:

> Rank these four model responses

you need both the option and its ordering:

```sql
ranked_options
--------------
answer_id
option_id
rank

PRIMARY KEY (answer_id, option_id)
UNIQUE (answer_id, rank)
```

So:

```text
answer_id | option_id | rank
----------+-----------+-----
500       | 22        | 1
500       | 19        | 2
500       | 21        | 3
500       | 20        | 4
```

Again, properly relational rather than JSON.

---

# The useful trick: **families**, not individual field types

I would avoid tables like:

```text
radio_answers
dropdown_answers
pairwise_answers
rating_answers
likert_answers
```

because those aren't actually different data structures.

Instead:

```text
                         Field UI
                            │
        ┌───────────────────┼────────────────────┐
        │                   │                    │
    dropdown             radio              pairwise
        │                   │                    │
        └───────────────────┼────────────────────┘
                            │
                       SINGLE_OPTION
                            │
                     selected_options
```

Likewise:

```text
short_text ─────┐
long_text  ─────┼──→ TEXT ───→ text_answers
code        ────┘
```

and:

```text
stars    ───────┐
likert   ───────┼──→ INTEGER ─→ integer_answers
integer_input ──┘
```

This is probably the key architectural decision I'd make for your system.

---

# There's an alternative I might actually choose

The fully normalized subtype model above is theoretically clean, but:

```sql
answers
text_answers
integer_answers
decimal_answers
boolean_answers
```

creates a lot of joins.

For a production application, I would seriously consider putting the scalar types directly onto `answers`:

```sql
answers
-------
id
submission_id
field_id

text_value       text
integer_value    bigint
decimal_value    numeric
boolean_value    boolean
```

with a constraint that at most one is non-null.

Then relational values still get child tables:

```sql
selected_options
ranked_options
bounding_boxes
...
```

This means:

```text
              answers
           /     |      \
 text_value   int_value  ...
      |
 simple scalar values
```

while complex answers become:

```text
answers
   │
   ├── selected_options
   ├── ranked_options
   ├── bounding_boxes
   ├── text_spans
   └── ...
```

Some database purists may dislike the nullable columns, but **I think this is the better practical design**.

It's still normalized in the important sense: you're not duplicating data, options are entities, responses aren't opaque blobs, and complex one-to-many data gets proper relations.

---

# I would also separate "question" from "field"

For your particular product, this could matter.

Consider:

> **Which response is better?**

Then display:

```text
Prompt:
"Explain relativity"

Response A:
"..."

Response B:
"..."

[ A is better ] [ B is better ] [ Tie ]
```

The prompt, Response A, and Response B aren't necessarily **fields**. They're content.

I'd probably have:

```text
form_elements
-------------
id
form_version_id
type
position
```

with subtypes such as:

```text
content_elements
input_fields
```

Or just separate:

```text
blocks
fields
```

because otherwise you eventually end up pretending every visible thing is a question.

For AI annotation specifically, something like this is more natural:

```text
Task Definition
│
├── blocks
│   ├── prompt
│   ├── model_response
│   ├── image
│   ├── instructions
│   └── separator/heading/etc.
│
└── fields
    ├── pairwise_choice
    ├── confidence
    └── explanation
```

---

# Complex annotation fields

Once you get into things like image segmentation, I'd stop trying to force them through generic form-answer primitives.

For example:

```sql
bounding_box_answers
--------------------
id
answer_id
label_option_id
x
y
width
height
```

One answer can contain many boxes:

```text
Answer
 ├── dog     x=.10 y=.20 w=.30 h=.40
 ├── person  x=.50 y=.15 w=.20 h=.70
 └── car     x=.20 y=.60 w=.50 h=.25
```

Text labeling might be:

```sql
text_span_answers
-----------------
id
answer_id
label_option_id
start_offset
end_offset
```

Segmentation could involve:

```sql
segmentation_regions
--------------------
id
answer_id
label_option_id
geometry / mask_asset_id
```

So the generic `answers` record is still useful as the root:

```text
Answer
    ├── scalar
    ├── options[]
    ├── ranked_options[]
    ├── bounding_boxes[]
    ├── text_spans[]
    └── segmentation_regions[]
```

---

## My preferred schema

Putting it all together, I'd probably start with:

```text
forms
form_versions

fields
├── text_field_config
├── numeric_field_config
├── choice_field_config
└── ...

field_options

submissions

answers
├── text_value
├── integer_value
├── decimal_value
├── boolean_value
│
├── selected_options[]
├── ranked_options[]
├── bounding_boxes[]
├── text_spans[]
└── ...
```

And the critical invariant would be:

> **A field's UI type determines which answer representation is valid.**

For example:

```text
short_text       → answers.text_value

long_text        → answers.text_value

rating           → answers.integer_value

slider           → answers.decimal_value

boolean          → answers.boolean_value

radio            → selected_options, max 1

dropdown         → selected_options, max 1

pairwise_choice  → selected_options, max 1

checkboxes       → selected_options, many

ranking          → ranked_options

bounding_box     → bounding_boxes

text_annotation  → text_spans
```

That gives you a schema that is **quite normalized without making "every new UI component requires three new tables" your architecture**.

And for your application specifically, I'd make the list of fundamental **answer representations** deliberately small. You can potentially have dozens of task/question types while only needing perhaps 8–12 underlying answer structures.






# Me
> I like this approach for the form schema, but I'm not sire it will fit very well for forms that are not designed inside QuickTrain, for example, when a customer imports a dataset to have annotated


Yes. For imported datasets, **the form should not be the root model**. The dataset and annotation task should be primary; forms are only one possible annotation interface.

## Separate three concepts

```text
Dataset
├── items/assets
├── imported metadata
└── source annotations

Annotation project
├── dataset
├── annotation schema/ontology
├── assignment rules
└── annotation submissions

Form
└── optional UI for collecting project annotations
```

## Suggested model

```text
datasets
-------
id
name
source
external_id
metadata
```

```text
dataset_items
-------------
id
dataset_id
external_id
payload
metadata
```

`payload` can reference images, documents, audio, model responses, or other assets. It should not be forced into form fields.

Then:

```text
annotation_projects
-------------------
id
dataset_id
name
annotation_type
schema_id
```

```text
annotation_schemas
------------------
id
name
definition
```

The schema describes valid annotations, for example:

```text
image_classification → one label
object_detection     → many boxes + labels
text_span_labeling   → many spans + labels
pairwise_preference  → one selected option
```

## Forms become optional views

A project may use:

```text
annotation_projects
└── form_id
```

The form defines how an annotator interacts with the task. Its fields produce annotations against a dataset item.

```text
annotation_tasks
----------------
id
project_id
dataset_item_id
assigned_user_id
status
```

```text
annotations
-----------
id
task_id
schema_id
created_by
```

Then use typed child records:

```text
classification_annotations
object_annotations
span_annotations
preference_annotations
ranking_annotations
```

These can reuse the same answer structures you proposed, but they are not necessarily called `answers`, because imported annotations may originate from a customer, a model, or another system rather than a form submission.

## Important distinction

A form response means:

> An annotator completed this UI form.

An annotation means:

> This label or geometry applies to this dataset item.

A form can produce annotations, but annotations may also be imported directly.

For example:

```text
Imported customer annotation
        └── object_annotation
             ├── dataset_item_id
             ├── label
             └── bounding box
```

No form is required.

## Imports

Use import batches for provenance and idempotency:

```text
dataset_imports
---------------
id
dataset_id
source
external_batch_id
imported_at
```

Imported records should preserve:

- source and external IDs
- original payload or asset reference
- import batch
- source annotation data
- mapping/import errors
- source schema version, if provided

This lets QuickTrain support both:

```text
Customer dataset → direct annotations
Customer dataset → QuickTrain form → new annotations
```

The core principle is:

> **Forms describe interaction; annotation schemas describe data; datasets provide the things being annotated.**



# Me
> But the are logically linked, as in each piece of data in a dataset (e.g a collection of text responses, or a collection of images) will have multiple questions (e.g a form) that the customer wants users to answer about each piece of data. I don't think it makes sense to create form records and form question records for each piece of data 

Correct. The form should be a **reusable annotation template**, not duplicated per dataset item.

```text
Organization
├── Dataset
│   ├── Dataset items
│   └── Import metadata
│
└── Annotation project
    ├── Form/version or annotation schema
    ├── Questions/fields
    ├── Tasks
    └── Answers
```

For example:

```text
forms
-----
id
organization_id
name
```

```text
form_versions
-------------
id
form_id
version
```

```text
fields
------
id
form_version_id
key
type
configuration
position
```

The form is then attached to an annotation project:

```text
annotation_projects
-------------------
id
organization_id
dataset_id
form_version_id       -- nullable for direct/imported annotation
annotation_schema_id
```

Each dataset item receives a task, not a form:

```text
annotation_tasks
----------------
id
project_id
dataset_item_id
assigned_user_id
status
```

Answers belong to the task and field:

```text
answers
-------
id
task_id
field_id
...
```

So if a dataset has 100,000 text responses and the form has 5 questions:

```text
1 form
1 form version
5 fields
100,000 dataset items
100,000 tasks per annotation pass
up to 500,000 answers
```

The form questions are defined once and reused across every item.

For imported annotations, `form_version_id` can be `NULL`. The project can instead use an `annotation_schema_id`, and imported annotations attach directly to dataset items or tasks.

The key distinction is:

- **Form/fields**: reusable definition of what users should answer.
- **Dataset items**: the data being evaluated.
- **Tasks**: an assignment to annotate one dataset item.
- **Answers**: the resulting values for that task.

A form could also be reused across multiple datasets, provided its version remains compatible with the project’s annotation schema.