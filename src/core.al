module agenticcrm.core

entity CRMConfig
{
    id UUID @id  @default(uuid()),
    gmailEmail String,
    ownerId String
}

record ContactInfo
{
    contactEmail String,
    contactFirstName String,
    contactLastName String,
    meetingTitle String,
    meetingBody String,
    meetingDate String
}

record ContactSearchResult
{
    contactFound Boolean,
    existingContactId String @optional
}

record EmailFilterResult
{
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

record SkipResult
{
    skipped Boolean,
    reason String
}

event findContactByEmail
{
    email String
}

workflow findContactByEmail {
   {hubspot/Contact {email? findContactByEmail.email}} @as foundContacts;
   if (foundContacts.length > 0) {
            foundContacts @as [firstContact];
    {ContactSearchResult {
            contactFound true,
            existingContactId firstContact.id
    }} @as csr;
    console.log(csr);
    csr
    } else {
        {ContactSearchResult {
            contactFound false
        }} @as csr;
    csr
    }
}
event createHubspotContact
{
    email String,
    firstName String,
    lastName String
}

workflow createHubspotContact {
    {hubspot/Contact {
        email createHubspotContact.email,
        first_name createHubspotContact.firstName,
        last_name createHubspotContact.lastName
    }} @as contact;
    {ContactSearchResult {
        contactFound true,
        existingContactId contact.id
    }} @as contactResult;
    contactResult
}
event createMeeting
{
    meetingTitle String,
    meetingBody String,
    meetingDate String,
    ownerId String,
    contactId String
}

workflow createMeeting {
    {hubspot/Meeting {
        meeting_title createMeeting.meetingTitle,
        meeting_body createMeeting.meetingBody,
        meeting_date createMeeting.meetingDate,
        owner createMeeting.ownerId,
        associated_contacts createMeeting.contactId}
    }
}

agent filterEmail
{
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

Don't generate markdown format, just invoke the agenticcrm.core/EmailFilterResult and nothing else.

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticcrm.core/EmailFilterResult
}

decision emailShouldBeProcessed {
  case (shouldProcess == true) {
    ProcessEmail
  }
  case (shouldProcess == false) {
    SkipEmail
  }
}

agent parseEmailInfo
{
    llm "sonnet_llm",
    role "Extract contact information and meeting details from EmailFilterResult.",
    instruction "You have access to understand and parse the data extracted from EmailFilterResult scratchpad.

STEP 1: Extract emails and names from the EmailFilterResult scratchpad:
- From {{EmailFilterResult.emailSender}}: extract email address and name (if 'Name <email>' format, extract both.)
- From {{EmailFilterResult.emailRecipients}}: same extraction logic

STEP 2: Determine which participant is the CONTACT (not the user) - USE ONLY THE ACTUAL DATA PROVIDED:
- The gmail owner email is {{EmailFilterResult.gmailOwnerEmail}} - this person is the USER, NOT the contact
- CRITICAL: The contactEmail you return MUST NEVER equal {{EmailFilterResult.gmailOwnerEmail}}
- LOGIC: Compare the actual emails to identify the external contact:
  * Read the actual value of {{EmailFilterResult.emailSender}}
  * Read the actual value of {{EmailFilterResult.emailRecipients}}
  * Read the actual value of {{EmailFilterResult.gmailOwnerEmail}}
  * If emailSender = gmailOwnerEmail, then the contact is the person in emailRecipients
  * If emailRecipients = gmailOwnerEmail, then the contact is the person in emailSender
  * Extract the contact's email, firstName, and lastName from the person who is NOT the gmail owner
- FINAL VERIFICATION: Confirm contactEmail ≠ {{EmailFilterResult.gmailOwnerEmail}} before returning

STEP 3: Extract meeting details from the EmailFilterResult values:
- meetingTitle: exact value from {{EmailFilterResult.emailSubject}} field
- meetingDate: exact value from {{EmailFilterResult.emailDate}} field (keep ISO 8601 format)
- meetingBody: summarize the {{EmailFilterResult.emailBody}} in a descriptive clear structure. If there are action items mentioned, create numbered action items.

STEP 4: Return ContactInfo with ACTUAL extracted values from the scratchpad data:
- contactEmail: the ACTUAL email you extracted (not an example)
- contactFirstName: the ACTUAL first name you extracted (not an example)
- contactLastName: the ACTUAL last name you extracted (not an example, can be empty string if not found)
- meetingTitle: the ACTUAL {{EmailFilterResult.emailSubject}} value (not an example)
- meetingBody: the ACTUAL summarized {{EmailFilterResult.emailBody}} (not an example)
- meetingDate: the ACTUAL {{EmailFilterResult.emailDate}} value (not an example)

CRITICAL RULES - READ CAREFULLY:
- DO NOT use placeholder values like \"sam@something.com\" or \"Project Discussion\"
- DO NOT use example data - ONLY use the ACTUAL data from EmailFilterResult scratchpad
- DO NOT return empty strings - extract actual values from the provided data
- DO NOT create fictional data
- Extract contactFirstName and contactLastName from the name part of \"Name <email>\" format
- If names not in email format, try to find them in the email body (e.g., after \"Hi,\" or in signature)

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
    retry classifyRetry,
    responseSchema agenticcrm.core/ContactInfo
}

decision contactExistsCheck {
      case (contactFound == true) {
    ContactExists
  }
case (contactFound == false) {
    ContactNotFound
  }
}

workflow skipProcessing {
    {SkipResult {
    skipped true,
    reason "Email filtered out (automated sender or newsletter)"
  }}
}

flow crmManager {
 filterEmail --> emailShouldBeProcessed
emailShouldBeProcessed --> "SkipEmail" skipProcessing
emailShouldBeProcessed --> "ProcessEmail" parseEmailInfo
parseEmailInfo --> {findContactByEmail {email parseEmailInfo.contactEmail}}
findContactByEmail --> contactExistsCheck
contactExistsCheck --> "ContactExists" {createMeeting {meetingTitle parseEmailInfo.meetingTitle, meetingBody parseEmailInfo.meetingBody, meetingDate parseEmailInfo.meetingDate, ownerId EmailFilterResult.hubspotOwnerId, contactId ContactSearchResult.existingContactId}}
contactExistsCheck --> "ContactNotFound" {createHubspotContact {email parseEmailInfo.contactEmail, firstName parseEmailInfo.contactFirstName, lastName parseEmailInfo.contactLastName}}
createHubspotContact --> {createMeeting {meetingTitle parseEmailInfo.meetingTitle, meetingBody parseEmailInfo.meetingBody, meetingDate parseEmailInfo.meetingDate, ownerId EmailFilterResult.hubspotOwnerId, contactId ContactSearchResult.existingContactId}}
    }
@public agent crmManager
{
    llm "gpt_llm",
    role "You coordinate the complete CRM workflow: filter the email, extract contact and meeting information, find or create the contact in HubSpot, and create the meeting with proper associations."
}

workflow @after create:gmail/Email {
    {CRMConfig? {}} @as [crmConfig];
    "Email sender is: " + gmail/Email.sender + " Email recipients are: " + gmail/Email.recipients + " Email date is: " + gmail/Email.date + " Email subject is: " + gmail/Email.subject + " Email body is: " + gmail/Email.body + " Email thread_id is: " + gmail/Email.thread_id + " Gmail main owner email is: " + crmConfig.gmailEmail + " Hubspot Owner id is: " + crmConfig.ownerId  @as completeMessage;
    console.log(completeMessage);
    {crmManager {message completeMessage}}
}
