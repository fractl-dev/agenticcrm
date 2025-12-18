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

  STEP 1: IDENTIFY WHO IS THE EXTERNAL CONTACT
  - If the sender contains 'pratik@fractl.io', the external contact is the RECIPIENT
  - If the sender does NOT contain 'pratik@fractl.io', the external contact is the SENDER
  - Never extract pratik@fractl.io as the contact

  STEP 2: EXTRACT EMAIL ADDRESS
  - Extract ONLY the email address from angle brackets
  - Example: 'Ranga Rao <ranga@fractl.io>' → extract 'ranga@fractl.io'

  STEP 3: EXTRACT NAME
  - Parse the name from the email header
  - Example: 'Ranga Rao <ranga@fractl.io>' → 'Ranga Rao'
  - Split into first_name and last_name
  - Example: first_name='Ranga', last_name='Rao'

  STEP 4: RETURN THE EXTRACTED INFORMATION
  - Return contactEmail (the email address)
  - Return firstName (first name only)
  - Return lastName (last name only)

  CRITICAL RULES:
  - Extract ONLY - do NOT query or create anything
  - NEVER extract pratik@fractl.io as a contact",
  responseSchema agenticcrm.core/ContactInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "You search for existing HubSpot contacts."
  instruction "Your ONLY task is to search for an existing contact in HubSpot with email {{contactEmail}}.

  STEP 1: QUERY ALL HUBSPOT CONTACTS
  - Use: {hubspot/Contact? {}}
  - This returns all contacts with structure:
    {
      \"id\": \"350155650790\",
      \"properties\": {
        \"email\": \"ranga@fractl.io\",
        \"firstname\": \"Ranga\",
        \"lastname\": \"Rao\"
      }
    }

  STEP 2: LOOP THROUGH CONTACTS TO FIND MATCH
  - For each contact in the results, access: contact.properties.email
  - Compare contact.properties.email with {{contactEmail}}
  - If match found, extract contact.id (the top-level id)

  STEP 3: RETURN THE RESULTS
  - If contact found: return contactFound=true and existingContactId with the contact ID
  - If contact NOT found: return contactFound=false (existingContactId can be omitted)

  CRITICAL RULES:
  - Search ONLY - do NOT create or update anything
  - MUST query ALL contacts and loop through them
  - Access email at contact.properties.email (NOT contact.email)",
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

  STEP 1: EXTRACT EMAIL SUBJECT
  - Look for the email subject in the context
  - This will be the meeting title

  STEP 2: ANALYZE EMAIL BODY
  - Read the email body
  - Identify:
    * Meeting discussions
    * Key decisions
    * Action items
    * Important points

  STEP 3: PREPARE MEETING SUMMARY
  - Create a concise summary of the email
  - Focus on key points and action items
  - This will be the meeting body

  STEP 4: RETURN MEETING INFORMATION
  - Return meetingTitle with the email subject
  - Return meetingBody with the summary

  CRITICAL RULES:
  - Parse ONLY - do NOT create anything",
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

// FLOWS: Connect agents with decision-based routing
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

// Orchestrator agent
@public agent crmManager {
  role "You coordinate the contact and meeting creation workflow using deterministic decision-based routing."
}

// Workflow: Trigger on email arrival
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
