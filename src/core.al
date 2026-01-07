module agenticcrm.core

entity CRMConfig {
    id UUID @id @default(uuid()),
    gmailEmail String,
    ownerId String
}

record ContactInfo {
    contactEmail String,
    contactFirstName String,
    contactLastName String,
    meetingTitle String,
    meetingBody String,
    meetingDate String
}

record ContactSearchResult {
    contactFound Boolean,
    existingContactId String @optional
}

record ContactResult {
    finalContactId String
}

record EmailFilterResult {
    shouldProcess Boolean,
    gmailOwnerEmail String @optional,
    hubspotOwnerId String @optional,
    emailSender String @optional,
    emailRecipients String @optional,
    emailSubject String @optional,
    emailBody String @optional,
    emailDate String @optional,
    emailThreadId String @optional
}

record SkipResult {
    skipped Boolean,
    reason String
}

event FindContactByEmail {
    email String
}

workflow FindContactByEmail {
    {hubspot/Contact {email? FindContactByEmail.email}} @as foundContacts;

    if (foundContacts.length > 0) {
        foundContacts @as [firstContact];
        {ContactSearchResult {
            contactFound true,
            existingContactId firstContact.id
        }}
    } else {
        {ContactSearchResult {
            contactFound false
        }}
    }
}

@public agent filterEmail {
  llm "sonnet_llm",
  role "Understand email and analyze for CRM processing decisions.",
  instruction "You receive a complete message about an email and also, receive information about gmail email owner and hubspot owner id.

Access the email data from the message that was passed to the flow. The email contains
- sender: string like 'Name <email@domain.com>'
- recipients: string like 'Name <email@domain.com>'
- subject: the email subject line
- body: the email body content
- date: ISO 8601 timestamp

YOUR TASK: Analyze the email context and determine if this should be processed for CRM.

It should be processed if:
- Business discussion with clients/prospects
- Meeting coordination or follow-up
- Onboarding or sales conversation

It shouldn't be processed if:
- Automated sender (contains no-reply, noreply, automated)
- Newsletter (subject has unsubscribe, newsletter, digest)
- System notification or spam

IMPORTANT: You must return in this format with proper data extracted.
if it should be processed.
{
 \"shouldProcess\": true,
 \"gmailOwnerEmail\": gmail_main_owner_email,
 \"hubspotOwnerId\": hubspot_owner_id,
 \"emailSender\": sender,
 \"emailRecipients\": recipients,
 \"emailSubject\": subject,
 \"emailBody\": body,
 \"emailDate\": date,
 \"emailThreadId\": thread_id
}

else, if it shouldn't be processed, then,
{
 \"shouldProcess\": false
}

Don't generate markdown format, just invoke the agenticcrm.core/EmailFilterResult and nothing else.",
  responseSchema agenticcrm.core/EmailFilterResult,
  retry classifyRetry
}

decision emailShouldBeProcessed {
  case (shouldProcess == true) {
    ProcessEmail
  }
  case (shouldProcess == false) {
    SkipEmail
  }
}

@public agent parseEmailInfo {
  llm "sonnet_llm",
  role "Extract contact information and meeting details from EmailFilterResult.",
  instruction "You have access to understand and parse the data extracted from EmailFilterResult scratchpad.

STEP 1: Extract emails and names from the EmailFilterResult scratchpad:
- From {{EmailFilterResult.emailSender}}: extract email address and name (if 'Name <email>' format, extract both.)
- From {{EmailFilterResult.emailRecipients}}: same extraction logic

STEP 2: Determine which participant is the CONTACT (not the user), properly follow this and get it absolutely right:
- If {{EmailFilterResult.emailSender}} email matches {{EmailFilterResult.gmailOwnerEmail}}, then the {{EmailFilterResult.emailRecipients}} is the contact.
- If {{EmailFilterResult.emailRecipients}} email matches {{EmailFilterResult.gmailOwnerEmail}}, then the sender is the contact
- Example: If emailSender is john@something.com and emailRecipients is: sam@something.com and gmailOwnerEmail is: john@something.com, then, contact is sam@something.com and vice-versa.
- Extract contactEmail, contactFirstName (if present), contactLastName (if present) from the identified contact.

STEP 3: Extract meeting details from the EmailFilterResult values:
- meetingTitle: exact value from {{EmailFilterResult.emailSubject}} field
- meetingDate: exact value from {{EmailFilterResult.emailDate}} field (keep ISO 8601 format)
- meetingBody: summarize the {{EmailFilterResult.emailBody}} in a descriptive clear structure. If there are action items mentioned, create numbered action items.

STEP 4: Return ContactInfo with ACTUAL extracted values:
- contactEmail, contactFirstName, contactLastName
- meetingTitle, meetingBody, meetingDate

IMPORTANT:
DO NOT return empty strings - extract actual values from the provided data.
DO NOT create new data, you must absolutely use the data provided.
Try to figure out contactFirstName and contactLastName if not provided on sender or recipient from the email body which starts from abbreviation like: Hi, <>",
  responseSchema agenticcrm.core/ContactInfo,
  retry classifyRetry
}

@public agent findExistingContact {
  llm "gpt_llm",
  role "Search for an existing contact in HubSpot by email address.",
  instruction "IMPORTANT: Call agenticcrm.core/FindContactByEmail with the exact email from {{ContactInfo.contactEmail}}.

Return the result:
- contactFound: true or false
- existingContactId: the contact ID if found",
  responseSchema agenticcrm.core/ContactSearchResult,
  retry classifyRetry,
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
    llm "gpt_llm",
    role "Add existing contact into agenticcrm.core/ContactResult",
    instruction "IMPORTANT: Extract {{ContactSearchResult.existingContactId}} and return that as finalContactId",
    responseSchema agenticcrm.core/ContactResult,
    retry classifyRetry
}

@public agent createNewContact {
  llm "gpt_llm",
  role "Create a new contact in HubSpot CRM.",
  instruction "Create contact using hubspot/Contact with:
- email from {{Contactinfo.contactEmail}}
- first_name from {{Contactinfo.contactFirstName}}
- last_name from {{Contactinfo.contactLastName}}

IMPORTANT: Invoke the huspot/Contact tool and from it's generated response, only return the id as finalContactId.

Return finalContactId with the id from the created contact.",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry,
  tools [hubspot/Contact]
}

workflow skipProcessing {
  {SkipResult {
    skipped true,
    reason "Email filtered out (automated sender or newsletter)"
  }}
}

@public agent createMeeting {
  llm "sonnet_llm",
  role "Create a meeting record in HubSpot to log the email interaction.",
  instruction "Convert {{ContactInfo.meetingDate}} from ISO 8601 to Unix milliseconds.
Calculate end time as start + 3600000 (1 hour).

Create meeting using hubspot/Meeting with:
- meeting_title from {{ContactInfo.meetingTitle}}
- meeting_body from {{ContactInfo.meetingBody}}
- timestamp: Unix milliseconds as string
- meeting_outcome: 'COMPLETED'
- meeting_start_time: Unix milliseconds as string
- meeting_end_time: start + 3600000 as string
- owner from {{EmailFilterResult.hubspotOwnerId}}
- associated_contacts from {{ContactResult.finalContactId}} (use the contact ID provided)

All timestamps must be Unix milliseconds as strings.",
  retry classifyRetry,
  tools [hubspot/Meeting]
}

flow crmManager {
  filterEmail --> emailShouldBeProcessed
  emailShouldBeProcessed --> "SkipEmail" skipProcessing
  emailShouldBeProcessed --> "ProcessEmail" parseEmailInfo
  parseEmailInfo --> findExistingContact
  findExistingContact --> contactExistsCheck
  contactExistsCheck --> "ContactExists" updateExistingContact
  contactExistsCheck --> "ContactNotFound" createNewContact
  updateExistingContact --> createMeeting
  createNewContact --> createMeeting
}

@public agent crmManager {
  role "You coordinate the complete CRM workflow: filter the email, extract contact and meeting information, find or create the contact in HubSpot, and create the meeting with proper associations."
}

workflow @after create:gmail/Email {
    {CRMConfig? {}} @as [crmConfig];
    "Email sender is: " + gmail/Email.sender + " Email recipients are: " + gmail/Email.recipients + " Email date is: " + gmail/Email.date + " Email subject is: " + gmail/Email.subject + " Email body is: " + gmail/Email.body + " Email thread_id is: " + gmail/Email.thread_id + " Gmail main owner email is: " + crmConfig.gmailEmail + " Hubspot Owner id is: " + crmConfig.ownerId  @as completeMessage;

    console.log(completeMessage);
    {crmManager {message completeMessage}}
}
