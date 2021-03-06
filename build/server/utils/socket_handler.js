// Generated by CoffeeScript 1.9.2
var ImapReporter, Mailbox, SocketHandler, _, _onObjectCreated, _onObjectDeleted, _onObjectUpdated, _toClientObject, forgetClient, handleNewClient, inScope, io, ioServer, log, sockets, stream, updateClientScope,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

ImapReporter = require('../imap/reporter');

log = require('../utils/logging')('sockethandler');

ioServer = require('socket.io');

Mailbox = require('../models/mailbox');

stream = require('stream');

_ = require('lodash');

io = null;

sockets = [];

SocketHandler = exports;

SocketHandler.setup = function(app, server) {
  io = ioServer(server);
  ImapReporter.setIOReference(io);
  return io.on('connection', handleNewClient);
};

SocketHandler.notify = function(type, data, olddata) {
  var i, len, results1, socket;
  log.debug("notify", type);
  if (type === 'message.update' || type === 'message.create') {
    results1 = [];
    for (i = 0, len = sockets.length; i < len; i++) {
      socket = sockets[i];
      if (inScope(socket, data) || (olddata && inScope(socket, olddata))) {
        log.debug("notify2", type);
        results1.push(socket.emit(type, data));
      } else {
        results1.push(void 0);
      }
    }
    return results1;
  } else if (type === 'mailbox.update') {
    return Mailbox.getCounts(data.id, function(err, results) {
      var recent, ref, total, unread;
      if (results[data.id]) {
        ref = results[data.id], total = ref.total, unread = ref.unread, recent = ref.recent;
        data.nbTotal = total;
        data.nbUnread = unread;
        data.nbRecent = recent;
      }
      return io != null ? io.emit(type, data) : void 0;
    });
  } else {
    return io != null ? io.emit(type, data) : void 0;
  }
};

_toClientObject = function(docType, raw, callback) {
  if (docType === 'message') {
    return callback(null, raw.toClientObject());
  } else if (docType === 'account') {
    return raw.toClientObject(function(err, clientRaw) {
      if (err) {
        return callback(null, raw);
      } else {
        return callback(null, clientRaw);
      }
    });
  } else {
    return callback(null, raw.toObject());
  }
};

_onObjectCreated = function(docType, created) {
  return _toClientObject(docType, created, function() {
    return SocketHandler.notify(docType + ".create", created);
  });
};

_onObjectUpdated = function(docType, updated, old) {
  return _toClientObject(docType, updated, function() {
    return SocketHandler.notify(docType + ".update", updated, old);
  });
};

_onObjectDeleted = function(docType, id, old) {
  return SocketHandler.notify(docType + ".delete", id, old);
};

SocketHandler.wrapModel = function(Model, docType) {
  var _oldCreate, _oldDestroy, _oldUpdateAttributes;
  _oldCreate = Model.create;
  Model.create = function(data, callback) {
    return _oldCreate.call(Model, data, function(err, created) {
      if (!err) {
        _onObjectCreated(docType, created);
      }
      return callback(err, created);
    });
  };
  _oldUpdateAttributes = Model.prototype.updateAttributes;
  Model.prototype.updateAttributes = function(data, callback) {
    var old;
    old = _.cloneDeep(this.toObject());
    return _oldUpdateAttributes.call(this, data, function(err, updated) {
      if (!err) {
        _onObjectUpdated(docType, updated, old);
      }
      return callback(err, updated);
    });
  };
  _oldDestroy = Model.prototype.destroy;
  return Model.prototype.destroy = function(callback) {
    var id, old;
    old = this.toObject();
    id = old.id;
    return _oldDestroy.call(this, function(err) {
      if (!err) {
        SocketHandler.notify(docType + ".delete", id, old);
      }
      return callback(err);
    });
  };
};

inScope = function(socket, data) {
  var ref;
  log.debug("inscope", socket.scope_mailboxID, Object.keys(data.mailboxIDs));
  return (ref = socket.scope_mailboxID, indexOf.call(Object.keys(data.mailboxIDs), ref) >= 0) && socket.scope_before < data.date;
};

handleNewClient = function(socket) {
  log.debug('handleNewClient', socket.id);
  socket.emit('refreshes.status', ImapReporter.summary());
  socket.on('mark_ack', ImapReporter.acknowledge);
  socket.on('change_scope', function(scope) {
    return updateClientScope(socket, scope);
  });
  socket.on('disconnect', function() {
    return forgetClient(socket);
  });
  return sockets.push(socket);
};

updateClientScope = function(socket, scope) {
  log.debug('updateClientScope', socket.id, scope);
  socket.scope_before = new Date(scope.before || 0);
  return socket.scope_mailboxID = scope.mailboxID;
};

forgetClient = function(socket) {
  var index;
  log.debug("forgetClient", socket.id);
  index = sockets.indexOf(socket);
  if (index !== -1) {
    return sockets = sockets.splice(index, 1);
  }
};
