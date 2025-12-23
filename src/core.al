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
    ownerId String
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
  role "You extract contact information from email messages."
  instruction "Extract the external contact's email and name from the message.

The message contains:
- 'Email sender is: Name <email>'
- 'email recipient is: Name <email>'

RULES:
1. If sender contains 'pratik@fractl.io', extract from RECIPIENT
2. Otherwise, extract from SENDER
3. Extract email from inside angle brackets <>
4. Extract name from before angle brackets and split into firstName, lastName

Return the contactEmail, firstName, and lastName in the ContactInfo schema.",
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
  role "You search for a HubSpot owner by email address."
  instruction "Search for the owner with email 'pratik@fractl.io' in HubSpot.

Query using hubspot/Owner with: {hubspot/Owner {email? \"pratik@fractl.io\"}}

This returns a list of owners. Extract the id from the first owner in the results.
Return JSON: {\"ownerId\": \"<the owner id>\"}

If no owner is found, return {\"ownerId\": null}",
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
- {{ownerId}} = the owner ID for the meeting

Steps:
1. Get the current timestamp in Unix milliseconds
2. Create the meeting using hubspot/Meeting with:
   - meeting_title: use the actual value from {{meetingTitle}}
   - meeting_body: use the actual value from {{meetingBody}}
   - timestamp: the current timestamp you generated
   - meeting_outcome: \"COMPLETED\"
   - meeting_start_time: the current timestamp you generated
   - meeting_end_time: the current timestamp + 3600000
   - owner: use the actual value from {{ownerId}} (REQUIRED for HubSpot UI visibility)
   - associated_contacts: use the actual value from {{finalContactId}}

CRITICAL:
- Use the ACTUAL values from the scratchpad variables, not the variable names themselves.
- The owner field is REQUIRED for meetings to show in HubSpot UI.",
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
