module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "anthropic",
    config {
        "model": "claude-sonnet-4-5",
        "maxTokens": 21333,
        "enableThinking": false,
        "temperature": 0.7,
        "budgetTokens": 8192,
        "enablePromptCaching": true,
        "stream": false,
        "enableExtendedOutput": true
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
    console.log("Searching for contact with email: " + FindContactByEmail.email);
    {hubspot/Contact {email? FindContactByEmail.email}} @as foundContacts;
    console.log("Found contacts: " + foundContacts.length);

    if (foundContacts.length > 0) {
        foundContacts @as [firstContact];
        console.log("Contact found - ID: " + firstContact.id);
        {ContactSearchResult {
            contactFound true,
            existingContactId firstContact.id
        }}
    } else {
        console.log("No contact found for: " + FindContactByEmail.email);
        {ContactSearchResult {
            contactFound false
        }}
    }
}

@public agent parseEmailInfo {
  llm "llm01",
  role "Extract contact information from the email message."
  instruction "Extract the external contact's email and name from the message.

MESSAGE FORMAT:
'Email sender is: Name <email>, email recipient is: Name <email>, email subject is: ...'

STEP 1: Find sender text
Look for 'Email sender is:' and read everything after it until the comma.
Example: 'Email sender is: Pratik Karki <pratik@fractl.io>, email recipient...'
Sender text = 'Pratik Karki <pratik@fractl.io>'

STEP 2: Find recipient text
Look for 'email recipient is:' and read everything after it until the comma.
Example: 'email recipient is: Sarah Wilson <sarah@acmecorp.io>, email subject...'
Recipient text = 'Sarah Wilson <sarah@acmecorp.io>'

STEP 3: Choose which text to extract from
IF sender text contains 'pratik@fractl.io' THEN use recipient text
ELSE use sender text

STEP 4: Extract data from chosen text
contactEmail = copy EXACTLY the text between < and >
firstName = extract first word before <
lastName = extract second word before <

EXAMPLE 1:
Input: 'Email sender is: Pratik Karki <pratik@fractl.io>, email recipient is: Ranga Rao <ranga@fractl.io>, ...'
Sender has 'pratik@fractl.io' → Use recipient text
Extract from 'Ranga Rao <ranga@fractl.io>':
- contactEmail = 'ranga@fractl.io'
- firstName = 'Ranga'
- lastName = 'Rao'

EXAMPLE 2:
Input: 'Email sender is: Michael Chen <michael@techstartup.ai>, email recipient is: Pratik Karki <pratik@fractl.io>, ...'
Sender does NOT have 'pratik@fractl.io' → Use sender text
Extract from 'Michael Chen <michael@techstartup.ai>':
- contactEmail = 'michael@techstartup.ai'
- firstName = 'Michael'
- lastName = 'Chen'

CRITICAL GUARDRAILS:
- Copy the COMPLETE email address EXACTLY as it appears between < >
- Do NOT change or modify the domain (the part after @)
- Do NOT substitute domains with test.com, example.com, company.com, or any other domain
- If the email is user@specificdomain.io, keep it as user@specificdomain.io
- Extract character-by-character - do not retype or reconstruct the email",
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
Call hubspot/Contact with:
{hubspot/Contact {
  email \"{{contactEmail}}\",
  first_name \"{{firstName}}\",
  last_name \"{{lastName}}\"
}}

Replace {{}} with EXACT values from scratchpad - do not modify them.

EXAMPLE:
If contactEmail=\"ranga@fractl.io\", firstName=\"Ranga\", lastName=\"Rao\":
{hubspot/Contact {
  email \"ranga@fractl.io\",
  first_name \"Ranga\",
  last_name \"Rao\"
}}

STEP 2: Extract and return the ID
The tool returns an object with an id field.
Return:
{
  \"finalContactId\": \"<the id value>\"
}

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
  role "Find the HubSpot owner for pratik@fractl.io."
  instruction "Query HubSpot for owner:
{hubspot/Owner {email? \"pratik@fractl.io\"}}

IF query returns results:
- Extract the id from the first owner
- Return {\"ownerId\": \"<that id>\"}

IF query returns no results:
- Return {\"ownerId\": null}

GUARDRAIL: Return null gracefully if not found - do not fail the flow.",
  responseSchema agenticcrm.core/OwnerResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Owner]
}

@public agent parseEmailContent {
  llm "llm01",
  role "Extract meeting information from the email."
  instruction "Extract meeting title and body from the message.

MESSAGE FORMAT:
'..., email subject is: <SUBJECT>, and the email body is: <BODY>'

STEP 1: Extract meeting title
Find 'email subject is:' in the message.
Read everything after it until ', and the email body is:'
Copy this exact text = meetingTitle

STEP 2: Extract and summarize email body
Find 'and the email body is:' in the message.
Read everything after it.
Summarize focusing on:
- Key discussion points
- Decisions made
- Action items
This summary = meetingBody

EXAMPLE 1:
Input: '..., email subject is: Sprint Planning Notes, and the email body is: Hi team, discussed upcoming sprint. Key decisions: Focus on API integration. Action items: Jane prepares design mockups by Wednesday. Best, Alex'

Output:
- meetingTitle = 'Sprint Planning Notes'
- meetingBody = 'Discussed upcoming sprint. Decision: Focus on API integration. Action: Jane prepares design mockups by Wednesday.'

EXAMPLE 2:
Input: '..., email subject is: Client Feedback Session, and the email body is: Met with client today. They approved the new features. Next steps: 1) Deploy to staging 2) Schedule UAT for next week. Thanks, Sam'

Output:
- meetingTitle = 'Client Feedback Session'
- meetingBody = 'Client approved new features. Next steps: Deploy to staging, schedule UAT for next week.'

CRITICAL GUARDRAILS:
- Copy meetingTitle exactly as it appears - do not rephrase or shorten it
- Summarize meetingBody concisely but preserve all key information
- Do not add information that wasn't in the original email body",
  responseSchema agenticcrm.core/MeetingInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "Create a meeting in HubSpot with all required fields."
  instruction "Create a meeting in HubSpot.

YOU HAVE AVAILABLE:
- {{finalContactId}} - the contact ID to associate
- {{meetingTitle}} - the meeting title
- {{meetingBody}} - the meeting summary
- {{ownerId}} - the owner ID (may be null)

STEP 1: Generate current timestamp
Get current date and time.
Convert to Unix timestamp in milliseconds.
Example: 1735041600000

STEP 2: Calculate end time
Add 3600000 milliseconds (1 hour) to the timestamp from Step 1.
Example: 1735041600000 + 3600000 = 1735045200000

STEP 3: Create the meeting
Call hubspot/Meeting with ALL these fields:
{hubspot/Meeting {
  meeting_title \"{{meetingTitle}}\",
  meeting_body \"{{meetingBody}}\",
  timestamp \"<timestamp from Step 1>\",
  meeting_outcome \"COMPLETED\",
  meeting_start_time \"<timestamp from Step 1>\",
  meeting_end_time \"<timestamp from Step 2>\",
  owner \"{{ownerId}}\",
  associated_contacts \"{{finalContactId}}\"
}}

Replace ALL {{}} with actual values from scratchpad.
Use the timestamps you generated in Steps 1 and 2.

EXAMPLE:
If meetingTitle=\"API Integration Planning\", meetingBody=\"Discussed REST API architecture and timeline\", finalContactId=\"350155650790\", ownerId=\"89234567\":
{hubspot/Meeting {
  meeting_title \"API Integration Planning\",
  meeting_body \"Discussed REST API architecture and timeline\",
  timestamp \"1735041600000\",
  meeting_outcome \"COMPLETED\",
  meeting_start_time \"1735041600000\",
  meeting_end_time \"1735045200000\",
  owner \"89234567\",
  associated_contacts \"350155650790\"
}}

CRITICAL GUARDRAILS:
- Replace ALL {{variable}} with actual values from scratchpad
- Do NOT copy the example values - generate fresh timestamps based on current date/time
- Use actual numeric timestamps you generate, not placeholder text
- All timestamp fields must be Unix milliseconds (numbers like 1735041600000)
- meeting_outcome must be exactly \"COMPLETED\"
- If {{ownerId}} is null, omit the owner field entirely
- Use the EXACT value from {{finalContactId}} for associated_contacts field
- Use the EXACT value from {{meetingTitle}} - do not rephrase or modify it
- Use the EXACT value from {{meetingBody}} - do not rephrase or modify it",
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
  parseEmailContent --> findOwner
  findOwner --> createMeeting
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
