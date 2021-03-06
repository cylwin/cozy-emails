# [Cozy](http://cozy.io) Emails

Cozy Emails lets you read and write your emails from your Cozy. The project is about to start, here are the main features we want to have:

* Simple UI
* Read/write emails
* Multiple mailboxes
* Attachments management (synced with Files!)


## Install

We assume here that the Cozy platform is correctly [installed](http://cozy.io/host/install.html)
 on your server.

You can simply install the Emails application via the app registry. Click on
ythe *Chose Your Apps* button located on the right of your Cozy Home.

From the command line you can type this command:

    cozy-monitor install emails


## Contribution

You can contribute to the Cozy Emails in many ways:

* Pick up an [issue](https://github.com/mycozycloud/cozy-emails/issues?state=open) and solve it.
* Translate it in [a new language](https://github.com/mycozycloud/cozy-emails/tree/master/client/app/locales).

[![Stories in Ready](https://badge.waffle.io/mycozycloud/cozy-emails.png?label=ready)](https://waffle.io/mycozycloud/cozy-emails)


## Hack

Hacking the Emails app requires you [setup a dev environment](http://cozy.io/hack/getting-started/). Once it's done you can hack the emails just like it was your own app.

    git clone https://github.com/cozy/cozy-emails.git

Run it with:

    node server.js

Each modification of the server requires a new build, here is how to run a
build:

    cake build

Each modification of the client requires a specific build too.

    cd client
    brunch watch

### Naming conventions

We've adopted IMAP naming conventions, which means:
* Account: bound to a provider like Gmail
* Mailbox: equivalent to imap folder
* Message: an email
* Conversation: a thread of Message


## Tests


### Frontend

Tests suite is based on CasperJS. Tests data are loaded by cozy-fixtures. So,
prior to run it, you need to install additional tools:

    sudo apt-get install phantomjs
    sudo npm install casperjs -g # version >= 1.1 is required.
    sudo npm install cozy-fixtures -g

    npm run fixtures

To run the client's tests, you also need to start the server:

    coffee server.coffee

Then you can run the client's tests:

    npm run test:client

### Backend

[![Build Status](https://travis-ci.org/cozy/cozy-emails.png?branch=master)](https://travis-ci.org/cozy/cozy-emails)

Running tests requires a Vagrant. Tests load a Dovecot instance in a Vagrant
virtual machine.

Once done, type the following command into the Cozy Emails folder:

    cake tests

If you want to add mails to the test suite, type the following lines.

    cd node_modules/dovecot-testing
    npm link
    dovecot-testing import

In order to run the tests, you must only have the Data System started.
The tests wont pass if you already have an account in your data-system


### Mail Loader

Mail loader test is based on the Dovecot Testing repository.


## Icons

By [Fontawesome](http://fortawesome.github.io/Font-Awesome/).
Main icon by [Elegant Themes](http://www.elegantthemes.com/blog/freebie-of-the-week/beautiful-flat-icons-for-free).


## License

Cozy Emails is developed by Cozy Cloud and distributed under the AGPL v3 license.


## What is Cozy?

![Cozy Logo](https://raw.github.com/mycozycloud/cozy-setup/gh-pages/assets/images/happycloud.png)

[Cozy](http://cozy.io) is a platform that brings all your web services in the
same private space.  With it, your web apps and your devices can share data
easily, providing you
with a new experience. You can install Cozy on your own hardware where no one
profiles you.


## Community

You can reach the Cozy Community by:

* Chatting with us on IRC #cozycloud on irc.freenode.net
* Posting on our [Forum](https://groups.google.com/forum/?fromgroups#!forum/cozy-cloud)
* Posting issues on the [Github repos](https://github.com/mycozycloud/)
* Mentioning us on [Twitter](http://twitter.com/mycozycloud)

## Technical reference

You will find all relevant resources about Emails development under this section.

* https://github.com/cozy/cozy-guidelines

### Javascript

* ReactJS: http://facebook.github.io/react/
* Flux:
    * http://facebook.github.io/flux/
    * http://facebook.github.io/react/blog/2014/07/30/flux-actions-and-the-dispatcher.html
    * https://github.com/facebook/flux/blob/master/examples/flux-chat/
* Immutable: https://github.com/facebook/immutable-js/
* Underscore: http://underscorejs.org
* Backbone: http://backbonejs.org (used for Backbone.Router) -- will be discard at some point
* jQuery: http://jquery.com (used for `bootstrap/dropdown` and Backbone compatibility) -- will be discard at some point
* Polyglot: http://airbnb.github.io/polyglot.js/ (localization)
* Moment: http://momentjs.com/ (date manipulating and formatting)

### Layout and styles

* Bootstrap: http://getbootstrap.com
* Fontawesome: http://fortawesome.github.io/Font-Awesome/

### Useful resources

This section references RFC and resources to understand IMAP.

* [IMAP protocol](https://www.ietf.org/rfc/rfc2060.txt#7.2.2)
* [IMAP LIST command extensions](http://tools.ietf.org/html/rfc5258)
* [IMAP LIST command extensions for special-use mailboxes](http://tools.ietf.org/html/rfc6154#2)

* [jmap.io](http://jmap.io/) (it's IMAP-compliant but it is NOT IMAP)
