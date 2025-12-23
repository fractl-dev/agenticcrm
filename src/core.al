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
  role "Extract contact email and name from the message."
  instruction "The message format:
'Email sender is: Name <email>, email recipient is: Name <email>, email subject is: ...'

STEP 1: Locate sender
Find 'Email sender is:' in the message.
Read the text after it until the next comma.
This is the sender text.

STEP 2: Locate recipient
Find 'email recipient is:' in the message.
Read the text after it until the next comma.
This is the recipient text.

STEP 3: Choose which one to use
If sender text contains 'pratik@fractl.io': use recipient text
Otherwise: use sender text

STEP 4: Extract from the chosen text
contactEmail = text between < and >
firstName = first word before <
lastName = second word before <

Example input:
'Email sender is: Pratik Karki <pratik@fractl.io>, email recipient is: John Doe <john@doe.io>, email subject is: ...'

Expected output:
contactEmail = john@doe.io
firstName = John
lastName = Doe

CRITICAL: Use ONLY the exact text from the message. Do not generate fake emails/domains or names.",
  responseSchema agenticcrm.core/ContactInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "Search for a contact in HubSpot by email."
  instruction "You have: {{contactEmail}}

Call the tool: agenticcrm.core/FindContactByEmail with email={{contactEmail}}

The tool returns a ContactSearchResult.
Return exactly what the tool returns.",
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
  instruction "You have: {{existingContactId}}

Return this JSON:
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
  instruction "You have:
- {{contactEmail}}
- {{firstName}}
- {{lastName}}

Call hubspot/Contact tool to create a contact with:
{hubspot/Contact {
  email \"{{contactEmail}}\",
  first_name \"{{firstName}}\",
  last_name \"{{lastName}}\"
}}

Replace {{}} placeholders with actual values from your scratchpad.

The tool returns an object with an id field.
Extract that id and return:
{
  \"finalContactId\": \"<the id you extracted>\"
}",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent findOwner {
  llm "llm01",
  role "Find the HubSpot owner for pratik@fractl.io."
  instruction "Query HubSpot for owner with email pratik@fractl.io:
{hubspot/Owner {email? \"pratik@fractl.io\"}}

If the query returns results:
- Take the first owner from the results
- Extract the id field
- Return: {\"ownerId\": \"<that id>\"}

If the query returns empty or fails:
- Return: {\"ownerId\": null}",
  responseSchema agenticcrm.core/OwnerResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Owner]
}

@public agent parseEmailContent {
  llm "llm01",
  role "Extract meeting title and body from the message."
  instruction "The message format:
'..., email subject is: <TITLE>, and the email body is: <BODY>'

STEP 1: Extract meeting title
Find 'email subject is:' in the message.
Read everything after it until you reach ', and the email body is:'
This is the meetingTitle.

STEP 2: Extract and summarize meeting body
Find 'and the email body is:' in the message.
Read everything after it.
Summarize the key points, decisions, and action items.
This is the meetingBody.

Example input:
'..., email subject is: Project Discussion, and the email body is: We discussed the timeline. Action: Complete design by Friday.'

Expected output:
meetingTitle = Project Discussion
meetingBody = Discussed timeline. Action item: Complete design by Friday.",
  responseSchema agenticcrm.core/MeetingInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "Create a meeting in HubSpot."
  instruction "You have:
- {{finalContactId}} (the contact to associate)
- {{meetingTitle}} (the meeting title)
- {{meetingBody}} (the meeting summary)
- {{ownerId}} (the owner ID, might be null)

STEP 1: Generate timestamp
Get the current date and time.
Convert it to Unix timestamp in milliseconds.
Example: 1735041600000

STEP 2: Call hubspot/Meeting tool
{hubspot/Meeting {
  meeting_title \"{{meetingTitle}}\",
  meeting_body \"{{meetingBody}}\",
  timestamp \"<timestamp from step 1>\",
  meeting_outcome \"COMPLETED\",
  meeting_start_time \"<timestamp from step 1>\",
  meeting_end_time \"<timestamp from step 1 + 3600000>\",
  owner \"{{ownerId}}\",
  associated_contacts \"{{finalContactId}}\"
}}

CRITICAL:
- Replace ALL {{}} placeholders with actual values from scratchpad
- If {{ownerId}} is null, omit the owner field entirely
- Use the timestamp you generated, not a placeholder",
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
