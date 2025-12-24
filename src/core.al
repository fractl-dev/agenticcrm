module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config {
        "model": "gpt-5.2"
    }
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

record OwnerResult {
    ownerId String @optional
}

event FindContactByEmail {
    email String
}

workflow FindContactByEmail {
    console.log("=== FindContactByEmail: Searching for: " + FindContactByEmail.email);
    {hubspot/Contact {email? FindContactByEmail.email}} @as foundContacts;
    console.log("=== FindContactByEmail: Found " + foundContacts.length + " contacts");

    if (foundContacts.length > 0) {
        foundContacts @as [firstContact];
        console.log("=== FindContactByEmail: Contact exists - ID: " + firstContact.id);
        {ContactSearchResult {
            contactFound true,
            existingContactId firstContact.id
        }}
    } else {
        console.log("=== FindContactByEmail: No contact found, will create new");
        {ContactSearchResult {
            contactFound false
        }}
    }
}

event FindOwnerByEmail {
    email String
}

workflow FindOwnerByEmail {
    console.log("=== FindOwnerByEmail: Searching for: " + FindOwnerByEmail.email);
    {hubspot/Owner {email? FindOwnerByEmail.email}} @as foundOwners;
    console.log("=== FindOwnerByEmail: Found " + foundOwners.length + " owners");

    if (foundOwners.length > 0) {
        foundOwners @as [firstOwner];
        console.log("=== FindOwnerByEmail: Owner exists - ID: " + firstOwner.id);
        {OwnerResult {
            ownerId firstOwner.id
        }}
    } else {
        console.log("=== FindOwnerByEmail: No owner found, returning null");
        {OwnerResult {
            ownerId null
        }}
    }
}

@public agent parseEmailInfo {
  llm "llm01",
  role "Extract contact information from the email message."
  instruction "Extract the external contact's email and name from THE MESSAGE YOU RECEIVED.

The message format:
'Email sender is: Name <email>, email recipient is: Name <email>, email subject is: ...'

STEP 1: Find sender text in YOUR MESSAGE
Locate 'Email sender is:' in THE MESSAGE YOU RECEIVED.
Read everything after it until the comma.
This is the sender text from YOUR message.

STEP 2: Find recipient text in YOUR MESSAGE
Locate 'email recipient is:' in THE MESSAGE YOU RECEIVED.
Read everything after it until the comma.
This is the recipient text from YOUR message.

STEP 3: Choose which text to extract from
IF sender text contains 'pratik@fractl.io' THEN use recipient text
ELSE use sender text

STEP 4: Extract data from the chosen text FROM YOUR MESSAGE
contactEmail = copy EXACTLY the text between < and > from YOUR message
firstName = extract first word before < from YOUR message
lastName = extract second word before < from YOUR message

CRITICAL GUARDRAILS:
- Extract from THE MESSAGE YOU RECEIVED, not from examples
- Copy the COMPLETE email address EXACTLY as it appears in YOUR message
- Do NOT change or modify the domain
- Do NOT substitute with different domains
- Do NOT use example data - use ACTUAL data from YOUR message

EXAMPLES (for reference only - DO NOT use this data):
Example pattern: 'Email sender is: John Doe <john@company.io>, email recipient is: ...'
Would extract: contactEmail='john@company.io', firstName='John', lastName='Doe'

Your task: Extract from YOUR actual message, not these examples.",
  responseSchema agenticcrm.core/ContactInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "Search for contact in HubSpot."
  instruction "You have available: {{contactEmail}}

Call agenticcrm.core/FindContactByEmail with email={{contactEmail}}

Return the ContactSearchResult that the tool provides.",
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
  role "Return the existing contact ID."
  instruction "You have available: {{existingContactId}}

Return this exact JSON structure:
{
  \"finalContactId\": \"{{existingContactId}}\"
}

Replace {{existingContactId}} with the actual ID value from your scratchpad.",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent createNewContact {
  llm "llm01",
  role "Create a new contact in HubSpot."
  instruction "You have available:
- {{contactEmail}}
- {{firstName}}
- {{lastName}}

STEP 1: Create the contact
Use the hubspot/Contact tool to create a contact with:
- email: the EXACT value from {{contactEmail}}
- first_name: the EXACT value from {{firstName}}
- last_name: the EXACT value from {{lastName}}

STEP 2: Extract and return the ID
The tool returns an object with an id field.
Return JSON: {\"finalContactId\": \"<the id value>\"}

EXAMPLE:
If contactEmail=\"ranga@fractl.io\", firstName=\"Ranga\", lastName=\"Rao\":
Tool creates contact, returns id \"350155650790\"
You return: {\"finalContactId\": \"350155650790\"}

CRITICAL GUARDRAILS:
- Use the EXACT email from {{contactEmail}} - do not change the domain
- Use the EXACT firstName from {{firstName}} - do not modify it
- Use the EXACT lastName from {{lastName}} - do not modify it",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent findOwner {
  llm "llm01",
  role "Find the HubSpot owner."
  instruction "Step 1: Call the tool agenticcrm.core/FindOwnerByEmail
Pass: email = pratik@fractl.io

Step 2: The tool returns an OwnerResult with an ownerId field
Return exactly what the tool returned.",
  responseSchema agenticcrm.core/OwnerResult,
  retry agenticcrm.core/classifyRetry,
  tools [agenticcrm.core/FindOwnerByEmail]
}

@public agent parseEmailContent {
  llm "llm01",
  role "Extract meeting information from the email."
  instruction "Parse the message to extract meeting information.

Your message contains text in the format:
Email sender is: ..., email recipient is: ..., email subject is: TITLE_HERE, and the email body is: BODY_HERE

Task 1: Find the email subject
Look for the text after 'email subject is: ' and before ', and the email body is:'
Copy it exactly as meetingTitle

Task 2: Summarize the email body
Look for the text after 'and the email body is: '
Read all of it and create a brief summary as meetingBody

Return meetingTitle and meetingBody.",
  responseSchema agenticcrm.core/MeetingInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "Create a meeting in HubSpot with all required fields."
  instruction "Create a meeting in HubSpot using the hubspot/Meeting tool.

YOU HAVE AVAILABLE:
- {{finalContactId}} - the contact ID to associate
- {{meetingTitle}} - the meeting title
- {{meetingBody}} - the meeting summary
- {{ownerId}} - the owner ID (may be null)

STEP 1: Determine owner ID
If {{ownerId}} is null or not a valid integer, use \"85257652\"
Otherwise use the value from {{ownerId}}

STEP 2: Generate current timestamp
Get current date and time and convert to Unix timestamp in milliseconds.
Example: 1735041600000

STEP 3: Calculate end time
Add 3600000 milliseconds (1 hour) to the timestamp.
Example: 1735041600000 + 3600000 = 1735045200000

STEP 4: Use the hubspot/Meeting tool with ALL these fields:
- meeting_title: EXACT value from {{meetingTitle}}
- meeting_body: EXACT value from {{meetingBody}}
- timestamp: the Unix milliseconds timestamp you generated
- meeting_outcome: exactly \"COMPLETED\"
- meeting_start_time: the Unix milliseconds timestamp you generated
- meeting_end_time: the timestamp + 3600000
- owner: the owner ID from STEP 1
- associated_contacts: EXACT value from {{finalContactId}}

EXAMPLE:
Input values:
- meetingTitle = \"API Integration Planning\"
- meetingBody = \"Discussed REST API architecture and timeline\"
- finalContactId = \"350155650790\"
- ownerId = null
- Current timestamp = 1735041600000

You call the tool with:
- meeting_title: \"API Integration Planning\"
- meeting_body: \"Discussed REST API architecture and timeline\"
- timestamp: \"1735041600000\"
- meeting_outcome: \"COMPLETED\"
- meeting_start_time: \"1735041600000\"
- meeting_end_time: \"1735045200000\"
- owner: \"85257652\"
- associated_contacts: \"350155650790\"

CRITICAL GUARDRAILS:
- Generate fresh timestamps based on CURRENT date/time
- Use EXACT values from {{variables}} - do not modify
- All timestamps must be Unix milliseconds as strings
- Always provide owner field using fallback 85257652 if needed",
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Meeting]
}

flow crmManager {
  parseEmailInfo --> findExistingContact
  findExistingContact --> contactExistsCheck
  contactExistsCheck --> "ContactExists" updateExistingContact
  contactExistsCheck --> "ContactNotFound" createNewContact
  updateExistingContact --> parseEmailContent
  createNewContact --> parseEmailContent
  parseEmailContent --> findOwner
  findOwner --> createMeeting
}

@public agent crmManager {
  role "You coordinate the complete CRM workflow: extract contact information, find or create the contact in HubSpot, then extract meeting information and create the meeting with proper associations."
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
