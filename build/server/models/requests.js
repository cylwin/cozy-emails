// Generated by CoffeeScript 1.7.1
var americano;

americano = require('americano');

module.exports = {
  mailbox: {
    all: americano.defaultRequests.all
  },
  email: {
    all: americano.defaultRequests.all,
    byMailbox: function(doc) {
      return emit(doc.mailbox, doc);
    }
  }
};
