cozydb = require 'cozydb'

# Public: the mailbox model
class Mailbox extends cozydb.CozyModel
    @docType: 'Mailbox'
    @schema:
        accountID: String        # Parent account
        label: String            # Human readable label
        path: String             # IMAP path
        lastSync: String         # Date.ISOString of last full box synchro
        tree: [String]           # Normalized path as Array
        delimiter: String        # delimiter between this box and its children
        uidvalidity: Number      # Imap UIDValidity
        attribs: [String]        # [String] Attributes of this folder
        lastHighestModSeq: String # Last highestmodseq successfully synced
        lastTotal: Number         # Last imap total number of messages in box

    # map of account's attributes -> RFC6154 special use box attributes
    @RFC6154:
        draftMailbox:   '\\Drafts'
        sentMailbox:    '\\Sent'
        trashMailbox:   '\\Trash'
        allMailbox:     '\\All'
        junkMailbox:    '\\Junk'
        flaggedMailbox: '\\Flagged'

    # Public: create a box in imap and in cozy
    #
    # account - {Account} to create the box in
    # parent - {Mailbox} to create the box in
    # label - {String} label of the new mailbox
    #
    # Returns (callback) {Mailbox}
    @imapcozy_create: (account, parent, label, callback) ->
        if parent
            path = parent.path + parent.delimiter + label
            tree = parent.tree.concat label
        else
            path = label
            tree = [label]

        mailbox =
            accountID: account.id
            label: label
            path: path
            tree: tree
            delimiter: parent?.delimiter or '/'
            attribs: []

        ImapPool.get(account.id).doASAP (imap, cbRelease) ->
            imap.addBox2 path, cbRelease
        , (err) ->
            return callback err if err
            Mailbox.create mailbox, callback


    # Public: find selectable mailbox for an account ID
    # as an array
    #
    # accountID - id of the account
    #
    # Returns (callback) {Array} of {Mailbox}
    @getBoxes: (accountID, callback) ->
        Mailbox.rawRequest 'treeMap',
            startkey: [accountID]
            endkey: [accountID, {}]
            include_docs: true

        , (err, rows) ->
            return callback err if err
            rows = rows.map (row) ->
                new Mailbox row.doc

            callback null, rows

    # Public: find selectable mailbox for an account ID
    # as an id indexed object with only path attributes
    # @TODO : optimize this with a map/reduce request
    #
    # accountID - id of the account
    #
    # Returns (callback) [{Mailbox}]
    @getBoxesIndexedByID: (accountID, callback) ->
        Mailbox.getBoxes accountID, (err, boxes) ->
            return callback err if err
            boxIndex = {}
            boxIndex[box.id] = box for box in boxes
            callback null, boxIndex

    # Public: remove mailboxes linked to an account that doesn't exist
    # in cozy.
    # @TODO : optimize this with a map destroy
    #
    # existing - {Array} of {String} ids of existing accounts
    #
    # Returns (callback) [{Mailbox}] all remaining mailboxes
    @removeOrphans: (existings, callback) ->
        log.debug "removeOrphans"
        Mailbox.rawRequest 'treemap', {}, (err, rows) ->
            return callback err if err

            boxes = []

            async.eachSeries rows, (row, cb) ->
                accountID = row.key[0]
                if accountID in existings
                    boxes.push row.id
                    cb null
                else
                    log.debug "removeOrphans - found orphan", row.id
                    Mailbox.destroy row.id, (err) ->
                        log.error 'failed to delete box', row.id if err
                        cb null

            , (err) ->
                callback err, boxes

    # Public: get the recent, unread and total count of message for a mailbox
    #
    # mailboxID - {String} id of the mailbox
    #
    # Returns (callback) {Object} counts
    #           :recent - {Number} number of recent messages
    #           :total - {Number} total number of messages
    #           :unread - {Number} number of unread messages
    @getCounts: (mailboxID, callback) ->
        options = if mailboxID
            startkey: ['date', mailboxID]
            endkey: ['date', mailboxID, {}]
        else
            startkey: ['date', ""]
            endkey: ['date', {}]

        options.reduce = true
        options.group_level = 3

        Message.rawRequest 'byMailboxRequest', options, (err, rows) ->
            return callback err if err
            result = {}
            rows.forEach (row) ->
                [DATEFLAG, boxID, flag] = row.key
                result[boxID] ?= {unread: 0, total: 0, recent: 0}
                if flag is "!\\Recent"
                    result[boxID].recent = row.recent
                if flag is "!\\Seen"
                    result[boxID].unread = row.value
                else if flag is null
                    result[boxID].total = row.value

            callback null, result

    # Public: is this box the inbox
    #
    # Returns {Boolean} if its the INBOX
    isInbox: -> @path is 'INBOX'


    # Public: is this box selectable (ie. can contains mail)
    #
    # Returns {Boolean} if its selectable
    isSelectable: ->
        '\\Noselect' not in (@attribs or [])


    # Public: get this box usage by special attributes
    #
    # Returns {String} the account attribute to set or null
    RFC6154use: ->
        for field, attribute of Mailbox.RFC6154
            if attribute in @attribs
                return field

    # Public: try to guess this box usage by its name
    #
    # Returns {String} the account attribute to set or null
    guessUse: ->
        path = @path.toLowerCase()
        if /sent/i.test path
            return 'sentMailbox'
        else if /draft/i.test path
            return 'draftMailbox'
        else if /flagged/i.test path
            return 'flaggedMailbox'
        else if /trash/i.test path
            return 'trashMailbox'
        # @TODO add more


    # Public: wrap an async function (the operation) to get a connection from
    # the pool before performing it and release the connection once it is done.
    #
    # operation - a Function({ImapConnection} conn, callback)
    #
    # Returns (callback) the result of operation
    doASAP: (operation, callback) ->
        ImapPool.get(@accountID).doASAP operation, callback

    # Public: wrap an async function (the operation) to get a connection from
    # the pool and open the mailbox without error before performing it and
    # release the connection once it is done.
    #
    # operation - a Function({ImapConnection} conn, callback)
    #
    # Returns (callback) the result of operation
    doASAPWithBox: (operation, callback) ->
        ImapPool.get(@accountID).doASAPWithBox @, operation, callback

    # Public: wrap an async function (the operation) to get a connection from
    # the pool and open the mailbox without error before performing it and
    # release the connection once it is done. The operation will be put at the
    # bottom of the queue.
    #
    # operation - a Function({ImapConnection} conn, callback)
    #
    # Returns (callback) the result of operation
    doLaterWithBox: (operation, callback) ->
        ImapPool.get(@accountID).doLaterWithBox @, operation, callback


    # Public: get this mailbox's children mailboxes
    #
    # Returns (callback) an {Array} of {Mailbox}
    getSelfAndChildren: (callback) ->
        Mailbox.rawRequest 'treemap',
            startkey: [@accountID].concat @tree
            endkey: [@accountID].concat @tree, {}
            include_docs: true

        , (err, rows) ->
            return callback err if err
            rows = rows.map (row) -> new Mailbox row.doc

            callback null, rows


    # Public: destroy all mailboxes belonging to an account.
    #
    # accountID - {String} id of the account to destroy mailboxes from
    #
    # Returns (callback) at completion
    @destroyByAccount: (accountID, callback) ->
        Mailbox.rawRequest 'treemap',
                startkey: [accountID]
                endkey: [accountID, {}]

        , (err, rows) ->
            return callback err if err
            async.eachSeries rows, (row, cb) ->
                Mailbox.destroy row.id, (err) ->
                    log.error "Fail to delete box", err.stack or err if err
                    cb null # ignore one faillure
            , callback

    # Public: get all message ids in a box
    #
    # boxID - {String} the box id
    #
    # Returns (callback) a {Array} of {String}, ids of all message in the box
    @getAllMessageIDs: (boxID, callback) ->
        options =
            startkey: ['uid', boxID, 0]
            endkey: ['uid', boxID, 'a'] # = Infinity in couchdb collation
            reduce: false

        Message.rawRequest 'byMailboxRequest', options, (err, rows) ->
            callback err, rows?.map (row) -> row.id

    # Public: mark all messages in a box as ignoreInCount
    # keep looping but throw an error if one fail
    #
    # boxID - {String} the box id
    #
    # Returns (callback) at completion
    @markAllMessagesAsIgnored: (boxID, callback) ->
        Mailbox.getAllMessageIDs boxID, (err, ids) ->
            return callback err if err
            changes = {ignoreInCount: true}
            lastError = null
            async.eachSeries ids, (id, cbLoop) ->
                Message.updateAttributes id, changes, (err) ->
                    if err
                        log.error "markAllMessagesAsIgnored err", err
                        lastError = err
                    cbLoop null # loop anyway
            , (err) ->
                callback err or lastError



    # Public: rename a box in IMAP and Cozy
    #
    # newLabel - {String} the box updated label
    # newPath - {String} the box updated path
    #
    # Returns (callback) at completion
    imapcozy_rename: (newLabel, newPath, callback) ->
        log.debug "imapcozy_rename", newLabel, newPath
        @imap_rename newLabel, newPath, (err) =>
            log.debug "imapcozy_rename err", err
            return callback err if err
            @renameWithChildren newLabel, newPath, (err) ->
                return callback err if err
                callback null

    # Public: rename a box in IMAP
    #
    # newLabel - {String} the box updated label
    # newPath - {String} the box updated path
    #
    # Returns (callback) at completion
    imap_rename: (newLabel, newPath, callback) ->
        @doASAP (imap, cbRelease) =>
            imap.renameBox2 @path, newPath, cbRelease
        , callback

    # Public: delete a box in IMAP and Cozy
    #
    # Returns (callback) at completion
    imapcozy_delete: (account, callback) ->
        log.debug "imapcozy_delete"
        box = this

        async.series [
            (cb) =>
                @imap_delete cb
            (cb) ->
                log.debug "account.forget"
                account.forgetBox box.id, cb
            (cb) =>
                log.debug "destroyAndRemoveAllMessages"
                @destroyAndRemoveAllMessages cb
        ], callback

    # Public: delete a box in IMAP
    #
    # Returns (callback) at completion
    imap_delete: (callback) ->
        log.debug "imap_delete"
        @doASAP (imap, cbRelease) =>
            imap.delBox2 @path, cbRelease
        , callback



    # Public: rename a box and its children in cozy
    #
    # newPath - {String} the new path
    # newLabel - {String} the new label
    #
    # Returns (callback) {Array} of {Mailbox} updated boxes
    renameWithChildren: (newLabel, newPath, callback) ->
        log.debug "renameWithChildren", newLabel, newPath, @path
        depth = @tree.length - 1
        path = @path

        @getSelfAndChildren (err, boxes) ->
            log.debug "imapcozy_rename#boxes", boxes.length, depth
            return callback err if err

            async.eachSeries boxes, (box, cb) ->
                log.debug "imapcozy_rename#box", box
                changes = {}
                changes.path = box.path.replace path, newPath
                changes.tree = (item for item in box.tree)
                changes.tree[depth] = newLabel
                if box.tree.length is depth + 1 # self
                    changes.label = newLabel
                box.updateAttributes changes, cb
            , callback

    # Public: destroy a mailbox and sub-mailboxes
    # remove all message from it & its sub-mailboxes
    # returns fast after destroying mailbox & sub-mailboxes
    # in the background, proceeds to remove messages
    #
    # Returns  mailbox destroyed completion
    destroyAndRemoveAllMessages: (callback) ->

        @getSelfAndChildren (err, boxes) ->
            return callback err if err

            async.eachSeries boxes, (box, cb) ->
                box.destroy (err) ->
                    log.error "fail to destroy box #{box.id}", err if err
                    Message.safeRemoveAllFromBox box.id, (err) ->
                        if err
                            log.error """"
                                fail to remove msg of box #{box.id}""", err
                        # loop anyway
                        cb()
            , callback


    # Public: refresh mails in this box
    #
    # Returns (callback) {Boolean} shouldNotif whether or not new unread mails
    # have been fetched in this fetch
    imap_refresh: (options, callback) ->
        log.debug "refreshing box"
        if not options.supportRFC4551
            log.debug "account doesnt support RFC4551"
            @imap_refreshDeep options, callback

        else if @lastHighestModSeq
            @imap_refreshFast options, (err, shouldNotif) =>
                if err
                    log.warn "refreshFast fail (#{err.stack}), trying deep"
                    options.storeHighestModSeq = true
                    @imap_refreshDeep options, callback

                else
                    log.debug "refreshFastWorked"
                    callback null, shouldNotif

        else
            log.debug "no highestmodseq, first refresh ?"
            options.storeHighestModSeq = true
            @imap_refreshDeep options, callback


    # Public: refresh mails in this box using rfc4551. This is similar to
    # {::imap_refreshDeep} but faster if the server supports RFC4551.
    #
    # First, we ask the server for all updated messages since last
    # refresh. {Mailbox::_refreshGetImapStatus}
    #
    # Then we apply these changes in {Mailbox::_refreshCreatedAndUpdated}
    #
    # Because RFC4551 doesnt give a way for the server to indicate expunged
    # messages, at this point, we have all new and updated messages, but we
    # may still have messages in cozy that were expungeds in IMAP.
    # We refresh deletion if needed in {Mailbox::_refreshDeleted}
    #
    # Finally we store the new highestmodseq, so we can ask for changes
    # since this refresh. We also store the IMAP number of message because
    # it can be different from the cozy one due to twin messages.
    #
    # Returns (callback) {Boolean} shouldNotif whether or not new unread mails
    # have been fetched in this fetch
    imap_refreshFast: (options, callback) ->
        box = this

        noChange = false
        box._refreshGetImapStatus box.lastHighestModSeq, (err, status) ->
            return callback err if err
            {changes, highestmodseq, total} = status

            box._refreshCreatedAndUpdated changes, (err, info) ->
                return callback err if err
                log.debug "_refreshFast#aftercreates", info
                shouldNotif = info.shouldNotif
                noChange or= info.noChange

                box._refreshDeleted total, info.nbAdded, (err, info) ->
                    return callback err if err
                    log.debug "_refreshFast#afterdelete", info
                    noChange or= info.noChange

                    if noChange
                        #@TODO : may be we should store lastSync
                        callback null, false

                    else
                        changes =
                            lastHighestModSeq: highestmodseq
                            lastTotal: total
                            lastSync: new Date().toISOString()

                        box.updateAttributes changes, (err) ->
                            callback err, shouldNotif

    # Private: Fetch some information from recent changes to the box
    #
    # modseqno - {String} the last checkpointed modification sequence
    #
    # Returns (callback) an {Object} with properties
    #       :changes - an {Object} with keys=uid, values=[mid, flags]
    #       :highestmodseq - the highest modification sequence of this box
    #       :total - total number of messages in this box
    _refreshGetImapStatus: (modseqno, callback) ->
        @doLaterWithBox (imap, imapbox, cbReleaseImap) ->
            highestmodseq = imapbox.highestmodseq
            total = imapbox.messages.total
            changes = {}
            if highestmodseq is modseqno
                cbReleaseImap null, {changes, highestmodseq, total}
            else
                imap.fetchMetadataSince modseqno, (err, changes) ->
                    cbReleaseImap err, {changes, highestmodseq, total}

        , callback

    # Private: Apply creation & updates from IMAP to the cozy
    #
    # changes - the {Object} from {::_refreshGetImapStatus}
    #
    # Returns (callback) at completion
    _refreshCreatedAndUpdated: (changes, callback) ->
        box = this
        uids = Object.keys changes
        if uids.length is 0
            callback null, {shouldNotif: false, nbAdded: 0, noChange: true}
        else
            nbAdded = 0
            shouldNotif = false
            Message.indexedByUIDs box.id, uids, (err, messages) ->
                return callback err if err
                async.eachSeries uids, (uid, next) ->
                    [mid, flags] = changes[uid]
                    uid = parseInt uid
                    message = messages[uid]
                    if message
                        message.updateAttributes {flags}, next
                    else
                        Message.fetchOrUpdate box, {mid, uid}, (err, info) ->
                            shouldNotif = shouldNotif or info.shouldNotif
                            nbAdded += 1 if info?.actuallyAdded
                            next err
                , (err) ->
                    return callback err if err
                    callback null, {shouldNotif, nbAdded}


    # Private: Apply deletions from IMAP to the cozy
    #
    # imapTotal - {Number} total number of messages in the IMAP box
    # nbAdded   - {Number} number of messages added
    #
    # Returns (callback) at completion
    _refreshDeleted: (imapTotal, nbAdded, callback) ->

        lastTotal = @lastTotal or 0

        log.debug "refreshDeleted L=#{lastTotal} A=#{nbAdded} I=#{imapTotal}"

        # if the last message count + number of messages added is equal
        # to the current count, no message have been deleted
        if lastTotal + nbAdded is imapTotal
            error = "    NOTHING TO DO"
            callback null, {noChange: true}

        # else if it is inferior, it means our algo broke somewhere
        # throw an error, and let {::imap_refresh} do a deep refresh
        else if lastTotal + nbAdded < imapTotal
            log.warn """
              #{lastTotal} + #{nbAdded} < #{imapTotal} on #{@path}
            """
            error = "    WRONG STATE"
            callback new Error(error), noChange: true

        # else if it is superior, this means some messages has been deleted
        # in imap. We delete them in cozy too.
        else
            error = "    NEED DELETION"
            box = this
            async.series [
                (cb) -> Message.UIDsInCozy box.id, cb
                (cb) -> box.imap_UIDs cb
            ], (err, results) ->
                [cozyUIDs, imapUIDs] = results
                log.debug "refreshDeleted#uids", cozyUIDs.length,
                                                                imapUIDs.length

                deleted = (uid for uid in cozyUIDs when uid not in imapUIDs)
                log.debug "refreshDeleted#toDelete", deleted
                Message.byUIDs box.id, deleted, (err, messages) ->
                    log.debug "refreshDeleted#toDeleteMsgs", messages.length
                    async.eachSeries messages, (message, next) ->
                        message.removeFromMailbox box, false, next
                    , (err) ->
                        callback err, {noChange: false}

    # Public: refresh some mails from this box
    #
    # options - the parameter {Object}
    #   :limitByBox - {Number} limit nb of message by box
    #   :firstImport - {Boolean} is this part of the first import of an account
    #
    # Returns (callback) {Boolean} shouldNotif whether or not new unread mails
    # have been fetched in this fetch
    imap_refreshDeep: (options, callback) ->
        {limitByBox, firstImport, storeHighestModSeq} = options
        log.debug "imap_refreshDeep", limitByBox
        step = RefreshStep.initial options

        @imap_refreshStep step, (err, info) =>
            log.debug "imap_refreshDeepEnd", limitByBox
            return callback err if err
            unless limitByBox
                changes = lastSync: new Date().toISOString()
                if storeHighestModSeq
                    changes.lastHighestModSeq = info.highestmodseq
                    changes.lastTotal = info.total
                @updateAttributes changes, callback
            else
                callback null, info.shouldNotif


    # Public: compute the diff between the imap box and the cozy one
    #
    # laststep - {RefreshStep} the previous step
    #
    # Returns (callback) {Object} operations and {RefreshStep} the next step
    #           :toFetch - [{Object}(uid, mid)] messages to fetch
    #           :toRemove - [{String}] messages to remove
    #           :flagsChange - [{Object}(id, flags)] messages where flags
    #                            need update
    getDiff: (laststep, callback) ->
        log.debug "diff", laststep

        step = null
        box = this

        @doLaterWithBox (imap, imapbox, cbRelease) ->

            step = laststep.getNext(imapbox.uidnext)
            step.highestmodseq = imapbox.highestmodseq
            step.total = imapbox.messages.total
            if step is RefreshStep.finished
                return cbRelease null

            log.info "IMAP REFRESH", box.label, "UID #{step.min}:#{step.max}"

            async.series [
                (cb) -> Message.UIDsInRange box.id, step.min, step.max, cb
                (cb) -> imap.fetchMetadata step.min, step.max, cb
            ], cbRelease

        ,  (err, results) ->
            log.debug "diff#results"
            return callback err if err
            return callback null, null, step unless results
            [cozyIDs, imapUIDs] = results


            toFetch = []
            toRemove = []
            flagsChange = []

            for uid, imapMessage of imapUIDs
                cozyMessage = cozyIDs[uid]
                if cozyMessage
                    # this message is already in cozy, compare flags
                    imapFlags = imapMessage[1]
                    cozyFlags = cozyMessage[1]
                    diff = _.xor(imapFlags, cozyFlags)

                    # gmail is weird (same message has flag \\Draft
                    # in some boxes but not all)
                    needApply = diff.length > 2 or
                                diff.length is 1 and diff[0] isnt '\\Draft'

                    if needApply
                        id = cozyMessage[0]
                        flagsChange.push id: id, flags: imapFlags

                else # this message isnt in this box in cozy
                    # add it to be fetched
                    toFetch.push {uid: parseInt(uid), mid: imapMessage[0]}

            for uid, cozyMessage of cozyIDs
                unless imapUIDs[uid]
                    toRemove.push id = cozyMessage[0]

            callback null, {toFetch, toRemove, flagsChange}, step


    # Public: remove a batch of messages from the cozy box
    #
    # toRemove - {Array} of {String} ids of cozy messages to remove
    # reporter - {ImapReporter} will be incresead by 1 for each remove
    #
    # Returns (callback) at completion
    applyToRemove: (toRemove, reporter, callback) ->
        log.debug "applyRemove", toRemove.length
        async.eachSeries toRemove, (id, cb) =>
            Message.removeFromMailbox id, this, (err) ->
                reporter.onError err if err
                reporter.addProgress 1
                cb null

        , callback


    # Public: apply a batch of flags changes on messages in the cozy box
    #
    # flagsChange - {Array} of {Object}(id, flags) changes to make
    # reporter - {ImapReporter} will be incresead by 1 for each change
    #
    # Returns (callback) at completion
    applyFlagsChanges: (flagsChange, reporter, callback) ->
        log.debug "applyFlagsChanges", flagsChange.length
        async.eachSeries flagsChange, (change, cb) ->
            Message.applyFlagsChanges change.id, change.flags, (err) ->
                reporter.onError err if err
                reporter.addProgress 1
                cb null
        , callback

    # Public: fetch a serie of message from the imap box
    #
    # toFetch - {Array} of {Object}(mid, uid) msg to fetch
    # reporter - {ImapReporter} will be incresead by 1 for each fetch
    #
    # Returns (callback) {Boolean} shouldNotif if one newly fetched is unread
    applyToFetch: (toFetch, reporter, callback) ->
        log.debug "applyFetch", toFetch.length
        box = this
        toFetch.reverse()
        shouldNotif = false
        async.eachSeries toFetch, (msg, cb) ->
            Message.fetchOrUpdate box, msg, (err, result) ->
                reporter.onError err if err
                reporter.addProgress 1
                if result?.shouldNotif is true
                    shouldNotif = true
                # loop anyway, let the DS breath
                setTimeout (-> cb null), 50
        , (err) ->
            callback err, shouldNotif

    # Public: apply a mixed bundle of ops
    #
    # ops - a operation bundle
    #       :toFetch - {Array} of {Object}(mid, uid) msg to fetch
    #       :toRemove - {Array} of {String} ids of cozy messages to remove
    #       :flagsChange - {Array} of {Object}(id, flags) changes to make
    # isFirstImport - {Boolean} is this part of the first import of account
    #
    # Returns (callback) shouldNotif - {Boolean} was a new unread message
    # imported
    applyOperations: (ops, isFirstImport, callback) ->
        {toFetch, toRemove, flagsChange} = ops
        nbTasks = toFetch.length + toRemove.length + flagsChange.length

        outShouldNotif = false

        if nbTasks > 0
            reporter = ImapReporter.boxFetch @, nbTasks, isFirstImport

            async.series [
                (cb) => @applyToRemove     toRemove,    reporter, cb
                (cb) => @applyFlagsChanges flagsChange, reporter, cb
                (cb) =>
                    @applyToFetch toFetch, reporter, (err, shouldNotif) ->
                        return cb err if err
                        outShouldNotif = shouldNotif
                        cb null
            ], (err) ->
                if err
                    reporter.onError err
                reporter.onDone()
                callback err, outShouldNotif
        else
            callback null, outShouldNotif

    # Public: refresh part of a mailbox
    # @TODO : recursion is complicated, refactor this using async.while
    #
    # laststep - {RefreshStep} can be null, step references            -
    #
    # Returns (callback) an info {Object} with properties
    #       :shouldNotif - {Boolean} was a new unread message imported
    #       :highestmodseq - {String} the box highestmodseq at begining
    imap_refreshStep: (laststep, callback) ->
        log.debug "imap_refreshStep", laststep
        box = this
        @getDiff laststep, (err, ops, step) =>
            log.debug "imap_refreshStep#diff", err, ops

            return callback err if err

            info =
                shouldNotif: false
                total: step.total
                highestmodseq: step.highestmodseq

            unless ops
                return callback null, info
            else
                firstImport = laststep.firstImport
                @applyOperations ops, firstImport, (err, shouldNotif) =>
                    return callback err if err

                    # next step
                    @imap_refreshStep step, (err, infoNext) ->
                        return callback err if err
                        info.shouldNotif = shouldNotif or infoNext.shouldNotif
                        callback null, info


    # Public: get a message UID from its message id in IMAP
    #
    # messageID - {String} the message ID to find
    #
    # Returns (callback) {String} the message uid or null
    imap_UIDByMessageID: (messageID, callback) ->
        @doLaterWithBox (imap, imapbox, cb) ->
            imap.search [['HEADER', 'MESSAGE-ID', messageID]], cb
        , (err, uids) ->
            callback err, uids?[0]

    # Public: get all message UIDs in IMAP
    #
    # Returns (callback) {Array} of {String} all uids
    imap_UIDs: (callback) ->
        @doLaterWithBox (imap, imapbox, cb) ->
            imap.fetchBoxMessageUIDs cb
        , (err, uids) ->
            callback err, uids

    # Public: create a mail in IMAP if it doesnt exist yet
    # use for sent mail
    #
    # account - {Account} the account
    # message - {Message} the message
    #
    # Returns (callback) at task completion
    imap_createMailNoDuplicate: (account, message, callback) ->
        messageID = message.headers['message-id']
        mailbox = this
        @imap_UIDByMessageID messageID, (err, uid) ->
            return callback err if err
            return callback null, uid if uid
            account.imap_createMail mailbox, message, callback


    # Public: remove a mail in the given box
    # used for drafts
    #
    # uid - {Number} the message to remove
    #
    # Returns (callback) at completion
    imap_removeMail: (uid, callback) ->
        @doASAPWithBox (imap, imapbox, cbRelease) ->
            async.series [
                (cb) -> imap.addFlags uid, '\\Deleted', cb
                (cb) -> imap.expunge uid, cb
                (cb) -> imap.closeBox cb
            ], cbRelease
        , callback

    # Public: recover if this box has changed its UIDVALIDTY
    #
    # imap - the {ImapConnection}
    #
    # Returns (callback) at completion
    recoverChangedUIDValidity: (imap, callback) ->
        box = this

        imap.openBox @path, (err) ->
            return callback err if err
            # @TODO : split it by 1000
            imap.fetchBoxMessageIDs (err, messages) ->
                # messages is a map uid -> message-id
                uids = Object.keys(messages)
                reporter = ImapReporter.recoverUIDValidty box, uids.length
                async.eachSeries uids, (newUID, cb) ->
                    messageID = mailutils.normalizeMessageID messages[newUID]
                    Message.recoverChangedUID box, messageID, newUID, (err) ->
                        reporter.onError err if err
                        reporter.addProgress 1
                        cb null
                , (err) ->
                    reporter.onDone()
                    callback null

    # Public: BEWARE expunge (permanent delete) all mails from this box
    #
    # Returns (callback) at completion
    imap_expungeMails: (callback) ->
        box = this
        @doASAPWithBox (imap, imapbox, cbRelease) ->
            imap.fetchBoxMessageUIDs (err, uids) ->
                return cbRelease err if err
                return cbRelease null if uids.length is 0
                async.series [
                    (cb) -> imap.addFlags uids, '\\Deleted', cb
                    (cb) -> imap.expunge uids, cb
                    (cb) -> imap.closeBox cb
                    (cb) -> Message.safeRemoveAllFromBox box.id, (err) ->
                        if err
                            log.error """
                                fail to remove msg of box #{box.id}""", err
                        # loop anyway
                        cb()
                ], cbRelease
        , callback

    # Public: refresh part of a mailbox
    #
    # uid - uid to fetch
    #
    # Returns (callback) {Object}
    #        :shouldNotif - {Boolean} if the message was not read
    #        :actuallyAdded - {Boolean} always true
    Mailbox::imap_fetchOneMail = (uid, callback) ->
        @doLaterWithBox (imap, imapbox, cb) ->
            imap.fetchOneMail uid, cb

        , (err, mail) =>
            return callback err if err
            shouldNotif = '\\Seen' in (mail.flags or [])
            Message.createFromImapMessage mail, this, uid, (err) ->
                return callback err if err
                callback null, {shouldNotif: shouldNotif, actuallyAdded: true}

    # Public: whether this box messages should be ignored
    # in the account's total (trash or junk)
    #
    # Returns {Boolean} true if this message should be ignored.
    Mailbox::ignoreInCount = ->
        return Mailbox.RFC6154.trashMailbox in @attribs or
               Mailbox.RFC6154.junkMailbox  in @attribs or
               @guessUse() in ['trashMailbox', 'junkMailbox']


module.exports = Mailbox
Message = require './message'
log = require('../utils/logging')(prefix: 'models:mailbox')
_ = require 'lodash'
async = require 'async'
mailutils = require '../utils/jwz_tools'
ImapPool = require '../imap/pool'
ImapReporter = require '../imap/reporter'
{Break, NotFound} = require '../utils/errors'
{FETCH_AT_ONCE} = require '../utils/constants'

require('../utils/socket_handler').wrapModel Mailbox, 'mailbox'




# Public: store the state of a refresh
#
# Examples
#
#    step0 = RefreshStep.initial(100, false)
#    step1 = step0.getNext(30)
#    step1.min == 1 and step1.max == 30
#
#    step0 = RefreshStep.initial(100, false)
#    step1 = step0.getNext(1500)
#    step1.min == 1401 and step1.max == 1500
#
#    step0 = RefreshStep.initial(null, false)
#    step1 = step0.getNext(1500)
#    step1.min == 501 and step1.max == 1500
#    step2 = step1.getNext(1500) # 1500 is not used here
#    step2.min == 1 and step2.max == 500
class RefreshStep

    # a pseudo symbol for comparison
    @finished: {symbol: 'DONE'}

    # Public: get the first step.
    # The first step is marked as .initial = true and doesnt have min or max
    #
    # options - {Object}
    #       :limitByBox - {Number} max number of message to fetch in a box or
    #              null for all
    #       :firstImport - {Boolean}
    #
    # Returns {RefreshStep} an initial step
    @initial: (options) ->
        step = new RefreshStep()
        step.limitByBox = options.limitByBox
        step.firstImport = options.firstImport
        step.initial = true
        return step

    # Public: string representation of the step, used by console.log
    #
    # Returns {String} an human readable summary of the step
    inspect: ->
        "Step{ limit:#{@limitByBox} " +
        (if @initial then "initial" else "[#{@min}:#{@max}]") +
        (if @firstImport then ' firstImport' else '') + '}'


    # Public: compute the next step.
    # The step will have a [.min - .max] range of uid
    # of length = max(limitByBox, Constants.FETCH_AT_ONCE)
    #
    # uidnext - the box uidnext, which is always the upper limit of a
    #           box uids.
    #
    # Returns {RefreshStep} the next step
    getNext: (uidnext) ->
        log.debug "computeNextStep", this, "next", uidnext

        if @initial
            # pretend the last step was max: INFINITY, min: uidnext
            @min = uidnext + 1

        if @min is 1
            # uid are always > 1, we are done
            return RefreshStep.finished

        if @limitByBox and not @initial
            # the first step has the proper limitByBox size, we are done
            return RefreshStep.finished

        range = if @limitByBox then @limitByBox else FETCH_AT_ONCE

        step = new RefreshStep()
        step.firstImport = @firstImport
        step.limitByBox = @limitByBox
        # new max is old min
        step.max = Math.max 1, @min - 1
        # new min is old min - range
        step.min = Math.max 1, @min - range

        return step












