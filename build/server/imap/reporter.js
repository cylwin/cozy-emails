// Generated by CoffeeScript 1.9.2
var ImapReporter, Logger, _, io, ioServer, log, uuid,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

_ = require('lodash');

uuid = require('uuid');

ioServer = require('socket.io');

Logger = require('../utils/logging');

log = Logger('imap:reporter');

io = null;

module.exports = ImapReporter = (function() {
  ImapReporter.userTasks = {};

  ImapReporter.addUserTask = function(options) {
    return new ImapReporter(options);
  };

  ImapReporter.summary = function() {
    var id, ref, results, task;
    ref = ImapReporter.userTasks;
    results = [];
    for (id in ref) {
      task = ref[id];
      results.push(task.toObject());
    }
    return results;
  };

  ImapReporter.setIOReference = function(ioref) {
    return io = ioref;
  };

  ImapReporter.acknowledge = function(id) {
    var ref;
    if (id && ((ref = ImapReporter.userTasks[id]) != null ? ref.finished : void 0)) {
      delete ImapReporter.userTasks[id];
      return io != null ? io.emit('refresh.delete', id) : void 0;
    }
  };

  function ImapReporter(options) {
    this.toObject = bind(this.toObject, this);
    this.id = uuid.v4();
    this.done = 0;
    this.finished = false;
    this.errors = [];
    this.total = options.total;
    this.box = options.box;
    this.account = options.account;
    this.objectID = options.objectID;
    this.code = options.code;
    this.firstImport = options.firstImport;
    ImapReporter.userTasks[this.id] = this;
    if (io != null) {
      io.emit('refresh.create', this.toObject());
    }
  }

  ImapReporter.prototype.sendtoclient = function(nocooldown) {
    if (this.cooldown && !nocooldown) {
      return true;
    } else {
      if (io != null) {
        io.emit('refresh.update', this.toObject());
      }
      this.cooldown = true;
      return setTimeout(((function(_this) {
        return function() {
          return _this.cooldown = false;
        };
      })(this)), 500);
    }
  };

  ImapReporter.prototype.toObject = function() {
    return {
      id: this.id,
      finished: this.finished,
      done: this.done,
      total: this.total,
      errors: this.errors,
      box: this.box,
      account: this.account,
      code: this.code,
      objectID: this.objectID,
      firstImport: this.firstImport
    };
  };

  ImapReporter.prototype.onDone = function() {
    this.finished = true;
    this.done = this.total;
    this.sendtoclient(true);
    if (!this.errors.length) {
      return setTimeout((function(_this) {
        return function() {
          return ImapReporter.acknowledge(_this.id);
        };
      })(this), 3000);
    }
  };

  ImapReporter.prototype.onProgress = function(done) {
    this.done = done;
    return this.sendtoclient();
  };

  ImapReporter.prototype.addProgress = function(delta) {
    this.done += delta;
    return this.sendtoclient();
  };

  ImapReporter.prototype.onError = function(err) {
    this.errors.push(Logger.getLasts() + "\n" + err.stack);
    log.error("reporter err", err.stack);
    return this.sendtoclient();
  };

  return ImapReporter;

})();

ImapReporter.batchMoveToTrash = function(idsLength) {
  return new ImapReporter({
    code: 'batch-trash',
    total: idsLength
  });
};

ImapReporter.accountFetch = function(account, boxesLength, firstImport) {
  return new ImapReporter({
    total: boxesLength,
    account: account.label,
    objectID: account.id,
    code: 'account-fetch',
    firstImport: firstImport
  });
};

ImapReporter.boxFetch = function(box, total, firstImport) {
  return new ImapReporter({
    total: total,
    box: box.label,
    objectID: box.id,
    code: 'box-fetch',
    firstImport: firstImport
  });
};

ImapReporter.recoverUIDValidty = function(box, total) {
  return new ImapReporter({
    total: total,
    box: box.label,
    code: 'recover-uidvalidity'
  });
};
