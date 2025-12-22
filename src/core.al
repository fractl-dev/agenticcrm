module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config
    {"model": "gpt-5.2"}
}, @upsert}

agentlang/retry classifyRetry {
  attempts 3,
  backoff {
    strategy linear,
    delay 2,
    magnitude seconds,
    factor 2
  }
}

record ContactInfo {
    contactEmail String,
    firstName String,
    lastName String
}

record ContactSearchResult {
    contactFound Boolean,
    existingContactId String @optional
}

record ContactResult {
    finalContactId String
}

record MeetingInfo {
    meetingTitle String,
    meetingBody String
}

event FindContactByEmail {
    email String,
    contactFound Boolean @optional,
    existingContactId String @optional
}

workflow FindContactByEmail {
    {hubspot/Contact? {email? FindContactByEmail.email}} @as foundContacts;

    if (foundContacts <> []) {
        foundContacts @as [firstContact];
        {FindContactByEmail {
            email FindContactByEmail.email,
            contactFound true,
            existingContactId firstContact.id
        }}
    } else {
        {FindContactByEmail {
            email: FindContactByEmail.email,
            contactFound: false
        }}
    }
}

@public agent parseEmailInfo {
  llm "llm01",
  role "You extract email addresses and names from email messages."
  instruction "Your ONLY task is to parse the email message and extract contact information.

  MESSAGE FORMAT:
  The message will look like this:
  'Email sender is: Pratik Karki <pratik@fractl.io>, email recipient is: Ranga Rao <ranga@fractl.io>, email subject is: ...'

  STEP 1: IDENTIFY WHO IS THE EXTERNAL CONTACT
  - Look for 'Email sender is:' to find the sender
  - Look for 'email recipient is:' to find the recipient
  - If the sender contains 'pratik@fractl.io', the external contact is the RECIPIENT
  - If the sender does NOT contain 'pratik@fractl.io', the external contact is the SENDER
  - Never extract pratik@fractl.io as the contact

  STEP 2: EXTRACT EMAIL ADDRESS FROM THE EXTERNAL CONTACT
  - From the external contact field (sender or recipient), extract ONLY the email inside angle brackets <>
  - Example: 'Ranga Rao <ranga@fractl.io>' → extract 'ranga@fractl.io'
  - Example: 'John Doe <john@example.com>' → extract 'john@example.com'

  STEP 3: EXTRACT NAME FROM THE EXTERNAL CONTACT
  - From the external contact field, extract the name BEFORE the angle brackets
  - Example: 'Ranga Rao <ranga@fractl.io>' → extract 'Ranga Rao'
  - Split the name into firstName and lastName
  - Example: 'Ranga Rao' → firstName='Ranga', lastName='Rao'
  - Example: 'John Doe' → firstName='John', lastName='Doe'

  STEP 4: RETURN THE EXTRACTED INFORMATION
  - Return contactEmail (the email address from step 2)
  - Return firstName (first name from step 3)
  - Return lastName (last name from step 3)
  - Save these info to ContactInfo record as responseSchema

  EXAMPLE:
  Input: 'Email sender is: Pratik Karki <pratik@fractl.io>, email recipient is: Ranga Rao <ranga@fractl.io>...'
  - Sender contains pratik@fractl.io → External contact is RECIPIENT
  - Extract from recipient: 'Ranga Rao <ranga@fractl.io>'
  - contactEmail = 'ranga@fractl.io'
  - firstName = 'Ranga'
  - lastName = 'Rao'

  CRITICAL RULES:
  - Extract ONLY - do NOT query or create anything
  - NEVER extract pratik@fractl.io as a contact
  - Always extract from the correct field (sender OR recipient, not both)",
  responseSchema agenticcrm.core/ContactInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "You search for a HubSpot contact by email address."
  instruction "Search for a contact with email address {{contactEmail}} in HubSpot.

TARGET EMAIL: {{contactEmail}}

STEP 1: CREATE FindContactByEmail ENTITY
- Create an agenticcrm.core/FindContactByEmail entity with email={{contactEmail}}
- This will trigger a workflow that searches all HubSpot contacts
- The workflow will update the entity with the search results

STEP 2: READ THE RESULT FROM THE CREATED ENTITY
After creating the entity, read it back to get:
- contactFound: true/false (whether contact exists)
- existingContactId: the contact ID (if found)

STEP 3: RETURN THE RESULT

Return in this format:
- If contactFound=true: {\"contactFound\": true, \"existingContactId\": \"the ID\"}
- If contactFound=false: {\"contactFound\": false}

CRITICAL:
- CREATE agenticcrm.core/FindContactByEmail with email={{contactEmail}}
- After creation, the entity will have contactFound and existingContactId fields populated
- Return those values",
  responseSchema agenticcrm.core/ContactSearchResult,
  retry agenticcrm.core/classifyRetry,
  tools [agenticcrm.core/FindContactByEmail]
}

decision contactExistsCheck {
  case (contactFound == true) {
    ContactExists
  }
  case (contactFound == false) {
    ContactNotFound
  }
}

@public agent updateExistingContact {
  llm "llm01",
  role "You update existing HubSpot contacts and return the contact ID."
  instruction "Update the existing contact if needed, then return its ID.

CONTACT INFORMATION:
- Existing Contact ID: {{existingContactId}}
- First Name: {{firstName}}
- Last Name: {{lastName}}

STEP 1: Optionally update (if needed)
- You can use the hubspot/Contact tool to update
- If updating, use only: first_name, last_name
- Do NOT use: url, website, or other invalid fields

STEP 2: Return in THIS EXACT FORMAT
{
  \"finalContactId\": \"{{existingContactId}}\"
}

CRITICAL:
- You MUST return JSON with finalContactId
- The value should be {{existingContactId}} (the ID passed to you)
- This is the actual ID string like \"350155650790\"",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent createNewContact {
  llm "llm01",
  role "You create new HubSpot contacts and return the contact ID."
  instruction "Create a new contact in HubSpot and return its ID.

CONTACT TO CREATE:
- Email: {{contactEmail}}
- First Name: {{firstName}}
- Last Name: {{lastName}}

STEP 1: Create the contact
- Use the hubspot/Contact tool
- Create with these fields only: email, first_name, last_name
- Do NOT use: url, website, or other fields

STEP 2: Extract the ID
- Get the id from the created contact
- The id will be a string like \"350155650790\"

STEP 3: Return in THIS EXACT FORMAT
{
  \"finalContactId\": \"the actual ID like 350155650790\"
}

CRITICAL:
- You MUST return JSON with finalContactId
- The value must be the actual ID from the created contact
- Do NOT return code or syntax",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent parseEmailContent {
  llm "llm01",
  role "You parse email content to extract meeting information."
  instruction "Your ONLY task is to analyze the email and prepare meeting information.

  MESSAGE FORMAT:
  The message will look like this:
  'Email sender is: ..., email recipient is: ..., email subject is: Sixth meeting notes, and the email body is: Hi Ranga,...'

  STEP 1: EXTRACT EMAIL SUBJECT
  - Find the text that comes AFTER 'email subject is:' and BEFORE ', and the email body is:'
  - This entire text is the meeting title
  - Example: 'email subject is: Sixth meeting notes of the evening, and the email body is:...'
    → meetingTitle = 'Sixth meeting notes of the evening'

  STEP 2: EXTRACT EMAIL BODY
  - Find the text that comes AFTER 'and the email body is:'
  - This is the full email body text
  - Example: 'and the email body is: Hi Ranga,... Best, Pratik'
    → This entire text is the email body

  STEP 3: ANALYZE THE EMAIL BODY AND CREATE SUMMARY
  - Read the extracted email body from step 2
  - Identify:
    * Meeting discussions
    * Key decisions
    * Action items mentioned
    * Important points
  - Create a concise summary focusing on these elements

  STEP 4: RETURN MEETING INFORMATION
  - Return meetingTitle: the exact subject text from step 1
  - Return meetingBody: the summary you created in step 3

  EXAMPLE:
  Input: 'Email sender is: Pratik Karki <pratik@fractl.io>, email recipient is: Ranga Rao <ranga@fractl.io>, email subject is: Project Discussion, and the email body is: Hi Ranga, We discussed the project timeline. Action items: 1. Complete design by Friday. Best, Pratik'

  Output:
  - meetingTitle = 'Project Discussion'
  - meetingBody = 'Discussed project timeline. Action items: Complete design by Friday.'

  CRITICAL RULES:
  - Extract subject from the text AFTER 'email subject is:' and BEFORE ', and the email body is:'
  - Extract body from the text AFTER 'and the email body is:'
  - Parse ONLY - do NOT create meetings or contacts",
  responseSchema agenticcrm.core/MeetingInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "You create HubSpot meetings and associate them with contacts."
  instruction "Create a meeting in HubSpot with the information provided.

YOU HAVE THESE VALUES AVAILABLE:
- Contact ID: {{finalContactId}} (this is the actual contact ID to associate)
- Meeting Title: {{meetingTitle}} (this is the actual title from the email)
- Meeting Body: {{meetingBody}} (this is the actual summary of the email)

STEP 1: GENERATE CURRENT TIMESTAMP
- Get current date/time
- Convert to Unix milliseconds (numeric, like 1734434400000)

STEP 2: CREATE THE MEETING
Use the hubspot/Meeting tool with:
- meeting_title: the ACTUAL title value (NOT the word 'meetingTitle')
- meeting_body: the ACTUAL summary text (NOT the word 'meetingBody')
- timestamp: the numeric timestamp you generated
- associated_contacts: the ACTUAL contact ID (NOT the word 'finalContactId')

EXAMPLE OF WHAT TO CREATE:
If meetingTitle=\"Fifth meeting notes\" and meetingBody=\"Discussion about onboarding\" and finalContactId=\"350155650790\":
{hubspot/Meeting {
  meeting_title \"Fifth meeting notes\",
  meeting_body \"Discussion about onboarding team members and customers to the platform.\",
  timestamp \"1734434400000\",
  associated_contacts \"350155650790\"
}}

CRITICAL:
- Use the ACTUAL VALUES from the scratchpad, not the placeholder names
- Do NOT write {{meetingTitle}} - write the actual title
- Do NOT write {{meetingBody}} - write the actual body text
- Do NOT write {{finalContactId}} - write the actual ID",
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Meeting]
}

flow contactFlow {
  parseEmailInfo --> findExistingContact
  findExistingContact --> contactExistsCheck
  contactExistsCheck --> "ContactExists" updateExistingContact
  contactExistsCheck --> "ContactNotFound" createNewContact
}

flow meetingFlow {
  parseEmailContent --> createMeeting
}

flow crmManager {
  contactFlow --> meetingFlow
}

@public agent contactFlow {
  role "You manage the contact identification and creation workflow."
}

@public agent meetingFlow {
  role "You manage the meeting creation and association workflow."
}

@public agent crmManager {
  role "You coordinate the contact and meeting creation workflow using deterministic decision-based routing."
}

workflow @after create:gmail/Email {
    this.body @as emailBody
    this.sender @as emailSender
    this.recipients @as emailRecipients
    this.subject @as subject
    this.thread_id @as thread_id
    console.log("Email arrived:", emailBody)

    "Email sender is: " + this.sender + ", email recipient is: " + emailRecipients + ", email subject is: " + subject + ", and the email body is: " + emailBody @as emailCompleteMessage;

    {crmManager {message emailCompleteMessage}}
}
