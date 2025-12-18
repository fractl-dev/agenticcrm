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
  role "You search for existing HubSpot contacts by querying all contacts and looping through them."
  instruction "Your ONLY task is to find if a contact with email {{contactEmail}} already exists in HubSpot.

  YOU MUST FOLLOW THIS EXACT PROCESS:

  STEP 1: QUERY ALL EXISTING CONTACTS
  - Execute this query: {hubspot/Contact? {}}
  - This will return a list of ALL contacts in HubSpot
  - Each contact has this structure:
    {
      \"id\": \"350155650790\",
      \"properties\": {
        \"email\": \"ranga@fractl.io\",
        \"firstname\": \"Ranga\",
        \"lastname\": \"Rao\"
      }
    }

  STEP 2: LOOP THROUGH THE RESULTS TO FIND A MATCH
  - Go through each contact one by one
  - For EACH contact, check: contact.properties.email
  - Compare contact.properties.email with the target email: {{contactEmail}}
  - The email is nested under 'properties', NOT at the top level
  - If you find a match where contact.properties.email == {{contactEmail}}:
    * Extract the contact.id (this is at the TOP level, not in properties)
    * Remember this ID

  STEP 3: RETURN YOUR FINDINGS
  - If you FOUND a matching contact:
    * Set contactFound = true
    * Set existingContactId = the contact.id you found (e.g., \"350155650790\")
  - If you did NOT find any matching contact:
    * Set contactFound = false
    * Do not include existingContactId

  CRITICAL RULES:
  - You MUST query ALL contacts first using {hubspot/Contact? {}}
  - You MUST loop through the results to find matches
  - Do NOT create any contacts - this is search ONLY
  - Do NOT update any contacts - this is search ONLY
  - Access email at: contact.properties.email
  - Access ID at: contact.id (top level)
  - If no match is found, contactFound MUST be false",
  responseSchema agenticcrm.core/ContactSearchResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
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
  role "You update existing HubSpot contacts."
  instruction "Your ONLY task is to update an existing contact if new information is available.

  CONTACT TO UPDATE:
  - Contact ID: {{existingContactId}}
  - New information from email: firstName={{firstName}}, lastName={{lastName}}

  STEP 1: CHECK IF UPDATE IS NEEDED
  - Query the existing contact using {{existingContactId}}
  - Compare current data with new information

  STEP 2: UPDATE CONTACT (if needed)
  - If there's new information, UPDATE the contact using {{existingContactId}}
  - If no new information, skip update

  STEP 3: RETURN CONTACT ID
  - Return finalContactId with the value of {{existingContactId}}
  - This will be used by meeting creation

  CRITICAL RULES:
  - Update ONLY if there's new information
  - Access properties at contact.properties.*",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent createNewContact {
  llm "llm01",
  role "You create new HubSpot contacts."
  instruction "Your ONLY task is to create a new contact.

  CONTACT INFORMATION:
  - Email: {{contactEmail}}
  - First Name: {{firstName}}
  - Last Name: {{lastName}}

  STEP 1: CREATE NEW CONTACT
  - CREATE a new contact with the information above
  - Use field names: email, first_name, last_name

  STEP 2: RETURN CONTACT ID
  - Get the newly created contact.id
  - Return finalContactId with the contact ID
  - This will be used by meeting creation

  CRITICAL RULES:
  - Create ONLY - do NOT search
  - Access properties at contact.properties.*",
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
  instruction "Your ONLY task is to create a meeting and link it to the contact.

  MEETING INFORMATION:
  - Contact ID: {{finalContactId}}
  - Meeting Title: {{meetingTitle}}
  - Meeting Body: {{meetingBody}}

  STEP 1: GENERATE TIMESTAMP
  - Get the current date/time
  - Convert to Unix timestamp in milliseconds
  - Example: 1734434400000
  - MUST be a numeric value, NOT text

  STEP 2: CREATE THE MEETING
  - Create meeting with these fields:
    * meeting_title: use {{meetingTitle}}
    * meeting_body: use {{meetingBody}}
    * timestamp: the numeric Unix timestamp
    * associated_contacts: use {{finalContactId}}
  - Example:
    {hubspot/Meeting {
      meeting_title 'Re: Further Improvements on proposal',
      meeting_body 'Discussion about onboarding team members...',
      timestamp '1734434400000',
      associated_contacts '350155650790'
    }}

  CRITICAL RULES:
  - Create ONLY - do NOT search for contacts
  - Use numeric timestamp in milliseconds
  - Use 'timestamp' field name (NOT 'hs_timestamp')
  - Use 'associated_contacts' field with contact ID",
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
