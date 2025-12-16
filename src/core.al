module agenticcrm.core

delete {agentlang.ai/LLM {name? "llm01"}}

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config
    {"model": "gpt-4.1"}
}}

@public agent emailExtractorAgent {
  llm "llm01",
  role "You are an AI responsible for extracting information from gmail email and creating or updating hubspot contact."
  instruction "You receive complete information about email, you will need to extract information from that email,
  like: information about name, email, hubspot or other id information if present and also, summarize the information.
  You will then need to update contact if it is present on hubspot or else, you need to create a new hubspot contact, if it isn't present based on the information provided.
  The email sender/receipient pratik@fractl.io shouldn't be the contact that is created on hubspot because, they are the admin of hubspot.
  Properly parse the email body and extract information.",
  tools [hubspot/Contact]
}

@public agent meetingNotesAgent {
  llm "llm01",
  role "You are an AI responsible for creating or updating hubspot meeting information based on email interaction with the hubspot contact."
  instruction "You received an email containing meeting information or meeting discussion or breakthrough information that happened on email body message.
  Use it to create or update the meeting information for the contact.
  Basically, the meeting notes also needs to be summarized and information needs to be stored properly.
  Properly parse the email body and extract information.
  Additionally, make sure to add timestamp on hubspot/Meeting workflow.
  This field marks the date and time that the meeting occurred. You can use either a Unix timestamp in milliseconds or UTC format."
  tools [hubspot/Contact, hubspot/Meeting]
}

flow crmManager {
  emailExtractorAgent --> meetingNotesAgent
}

@public agent crmManager {
  role "You manage to create or update contact along with creation or updating the meeting notes with the contact."
}

workflow @after create:gmail/Email {
    this.body @as emailBody
    this.sender @as emailSender
    this.recipients @as emailReceipients
    this.subject @as subject
    this.thread_id @as thread_id
    console.log("Email arrived:", emailBody)

    "Email sender is: " + emailSender + ", email Receipient is: " + emailReceipients + ", email subject is: " + subject + " and the email body is: " + emailBody @as emailCompleteMessage;

    for c in {hubspot/Contact? {}} {
      if (emailSender <> c.email) {
        {crmManager {message emailCompleteMessage}}
      }
    }
    if (emailSender <> "pratik@fractl.io") {
        {crmManager {message emailCompleteMessage}}
    }
}
