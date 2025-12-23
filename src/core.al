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
  role "You literally extract text from the message without making any assumptions."
  instruction "Read the EXACT text from the message and extract email and name - do NOT generate or assume anything.

STEP 1: Find the sender text
Look for 'Email sender is:' and read everything after it until you hit a comma.
Example message: 'Email sender is: Pratik Karki <pratik@fractl.io>, email recipient is: ...'
Sender text = 'Pratik Karki <pratik@fractl.io>'

STEP 2: Find the recipient text
Look for 'email recipient is:' and read everything after it until you hit a comma.
Example message: '..., email recipient is: John Smith <john@example.com>, email subject is: ...'
Recipient text = 'John Smith <john@example.com>'

STEP 3: Choose which text to use
IF the sender text contains the string 'pratik@fractl.io' THEN use recipient text
ELSE use sender text

STEP 4: Extract from the chosen text
contactEmail = the text between < and > characters
firstName = the first word before the < character
lastName = the second word before the < character

ABSOLUTELY CRITICAL RULES:
- Extract ONLY from the actual message text provided
- DO NOT generate email addresses like 'user@domain.com' or 'name@example.com'
- DO NOT assume or make up any information
- LITERALLY copy the text from inside the angle brackets
- If you cannot find the exact pattern, extraction failed",
  responseSchema agenticcrm.core/ContactInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "You search for a HubSpot contact by email address."
  instruction "Search for a contact using the email {{contactEmail}}.

Use the agenticcrm.core/FindContactByEmail tool and return the ContactSearchResult it provides.",
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
  role "You return the existing contact ID."
  instruction "Return the existing contact ID.

Return JSON: {\"finalContactId\": \"{{existingContactId}}\"}

Use the actual ID value from {{existingContactId}}, not the placeholder text.",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent createNewContact {
  llm "llm01",
  role "You create new HubSpot contacts."
  instruction "Create a contact with email={{contactEmail}}, first_name={{firstName}}, last_name={{lastName}}.

Use hubspot/Contact tool with only these three fields.
Return JSON: {\"finalContactId\": \"<the ID from created contact>\"}",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent findOwner {
  llm "llm01",
  role "You search for the HubSpot owner by querying for pratik@fractl.io."
  instruction "Find the owner with email pratik@fractl.io.

Execute: {hubspot/Owner {email? \"pratik@fractl.io\"}}

If the query returns results:
- Extract the id field from the first owner
- Return {\"ownerId\": \"<that id value>\"}

If the query returns no results or fails:
- Return {\"ownerId\": null}

CRITICAL: Return null if owner not found, don't fail the entire flow.",
  responseSchema agenticcrm.core/OwnerResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Owner]
}

@public agent parseEmailContent {
  llm "llm01",
  role "You extract meeting information from email content."
  instruction "Extract meeting information from the message.

The message format is:
'..., email subject is: <SUBJECT>, and the email body is: <BODY>'

Extract:
1. meetingTitle: The text between 'email subject is:' and ', and the email body is:'
2. meetingBody: Summarize the text after 'and the email body is:' focusing on key discussion points and action items

Return meetingTitle and meetingBody in the MeetingInfo schema.",
  responseSchema agenticcrm.core/MeetingInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "You create HubSpot meetings with proper timestamps and associations."
  instruction "Create a meeting in HubSpot using the provided information.

Available values from scratchpad:
- {{finalContactId}} = the contact ID to associate
- {{meetingTitle}} = the meeting title
- {{meetingBody}} = the meeting body/summary
- {{ownerId}} = the owner ID (may be null)

Steps:
1. Get the current timestamp in Unix milliseconds
2. Create the meeting using hubspot/Meeting with:
   - meeting_title: use the actual value from {{meetingTitle}}
   - meeting_body: use the actual value from {{meetingBody}}
   - timestamp: the current timestamp you generated
   - meeting_outcome: \"COMPLETED\"
   - meeting_start_time: the current timestamp you generated
   - meeting_end_time: the current timestamp + 3600000
   - owner: use the actual value from {{ownerId}} ONLY if it is not null
   - associated_contacts: use the actual value from {{finalContactId}}

CRITICAL:
- Use the ACTUAL values from the scratchpad variables, not the variable names themselves
- If {{ownerId}} is null, DO NOT include the owner field at all
- The meeting will still be created without owner, it just won't show in some UI views",
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
