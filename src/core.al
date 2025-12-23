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
  role "Extract email and name from message text."
  instruction "Find 'Email sender is:' in the message. Read text after it until comma. This is sender.
Find 'email recipient is:' in the message. Read text after it until comma. This is recipient.

If sender contains 'pratik@fractl.io': use recipient. Otherwise: use sender.

From chosen text:
- contactEmail = text inside < >
- firstName = first word before <
- lastName = second word before <

Example:

Email sender is: Pratik Karki <pratik@fractl.io>, email recipient is: John Doe <john@doe.io>, email subject is: Discussion on things, and the email body is: Something happened.

From the above you need to pick like:
contactEmail = john@doe.io
firstName = John
lastName = Doe

Use ONLY exact text from message. Do not generate or assume anything. There might be different email domain, but, use whatever is provided.",
  responseSchema agenticcrm.core/ContactInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "Search contact by email."
  instruction "Call agenticcrm.core/FindContactByEmail with email={{contactEmail}}. Return the result.",
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
  role "Return contact ID."
  instruction "Return {\"finalContactId\": \"{{existingContactId}}\"}",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent createNewContact {
  llm "llm01",
  role "Create contact."
  instruction "Use hubspot/Contact to create contact:
- email: {{contactEmail}}
- first_name: {{firstName}}
- last_name: {{lastName}}

Return {\"finalContactId\": \"<id from created contact>\"}",
  responseSchema agenticcrm.core/ContactResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Contact]
}

@public agent findOwner {
  llm "llm01",
  role "Find owner."
  instruction "Query: {hubspot/Owner {email? \"pratik@fractl.io\"}}

If results found: return {\"ownerId\": \"<id from first result>\"}
If no results: return {\"ownerId\": null}",
  responseSchema agenticcrm.core/OwnerResult,
  retry agenticcrm.core/classifyRetry,
  tools [hubspot/Owner]
}

@public agent parseEmailContent {
  llm "llm01",
  role "Extract meeting info."
  instruction "Find text between 'email subject is:' and ', and the email body is:' = meetingTitle
Find text after 'and the email body is:' and summarize = meetingBody

Return both.",
  responseSchema agenticcrm.core/MeetingInfo,
  retry agenticcrm.core/classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "Create meeting."
  instruction "Get current timestamp in milliseconds.

Use hubspot/Meeting:
- meeting_title: {{meetingTitle}}
- meeting_body: {{meetingBody}}
- timestamp: current timestamp
- meeting_outcome: \"COMPLETED\"
- meeting_start_time: current timestamp
- meeting_end_time: current timestamp + 3600000
- owner: {{ownerId}} (only if not null)
- associated_contacts: {{finalContactId}}

Use actual values from scratchpad, not variable names.",
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
