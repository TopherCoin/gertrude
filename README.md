#Gertrude - #ant.org channel bot

##Description

Gertrude is the #ant.org channel bot. She's fifth generation implemented in Cinch; 
previous incarnations were in RBot, MozBot, infobot, and straight perl.

Gertrude is built on [cinch][], and adds a number of features like two-factor authentication,
mongo database-backed persistent configuration, and dynamic plugin management, plus a lot of
Natural Language Processing features.

Gertrude comes with many custom plugins.


##Installation

I can't imagine anyone wants to install their own gertrude, but if you do you'll need to install
[mongo][] and its ruby driver, and also the [enju][] parser (which can be run on a different host,
as gertrude does). 

You'll also need Yubikeys from [yubico][] in order to authenticate with the bot for admin tasks.
To add users to the database, use getrude/tools/user.rb. You'll need a Yubico API for each user/yubikey
combination you want gertrude to recognise.

[cinch] : https://github.com/cinchrb/cinch
[enju] :http://www.nactem.ac.uk/enju/
[yubico] : http://www.yubico.com/
