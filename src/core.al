module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config
    {"model": "gpt-4.1"}
}}

@public agent emailExtractorAgent {
  llm "llm01",
  role "You are an AI responsible for extracting information from email and creating or updating hubspot contact."
  instruction "You receive an email, you will need to extract information from that email, like: information about name, email, hubspot or other id information and also, summarize the information. You will then need to update contact if it is present on hubspot or else, you need to create a new hubspot contact, if it isn't present based on the information provided. Properly parse the email body and extract information.",
  tools [hubspot/Contact]
}

@public agent meetingNotesAgent {
  llm "llm01",
  role "You are an AI responsible for creating or updating hubspot meeting information based on email interaction with the hubspot contact."
  instruction "You received an email containing meeting information or meeting discussion. Use it to create or update the meeting information for the contact. Basically, the meeting notes also needs to be summarized and information needs to be stored properly. Properly parse the email body and extract information."
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
    this.subject @as subject
    this.thread_id @as thread_id
    console.log("Email arrived:", emailBody)

    for (c in {hubspot/Contact {}}) {
      if (emailSender <> c.email) {
        {emailAgent {message emailBody}} @as result
        if (result.result == "success") {
          {gmail/Email
            {sender "pratik@fractl.io", recipients emailSender, subject subject,
             body "Contact created/updated successfully", thread_id thread_id}}
        } else {
          {gmail/Email
            {sender "pratik@fractl.io", recipients emailSender, subject subject,
            body "Failed to create/update contact", thread_id thread_id}}
        }
      }
    }
}
