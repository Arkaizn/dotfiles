import QtQuick
import qs.components
import qs.services
import "MailIcons.js" as I

// Attachments viewed inside the app (like Thunderbird's PDF viewer): the
// shared FileViewer (images, PDFs rendered by poppler through mailsync.py
// `view`, text), plus "Save". ←/→ between the message's attachments,
// Ctrl +/-/0 or Ctrl + wheel zoom, Esc closes.
//   show(msg, attachments, index)
FileViewer {
    id: root

    property var msg: null

    function show(m, atts, i) {
        msg = m
        open(atts, i)
    }

    loader: (att, cb) => MailStore.view(msg, att.index, cb)
    actions: [{
        icon: I.download, text: "Save",
        run: (att, item, note) => MailStore.saveAttachment(root.msg, att.index, false, res => note(res.ok ? "Saved to " + res.path : res.error))
    }]
}
