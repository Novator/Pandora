#!/bin/sh

## These hot commands of Git are using for maintenance of Pandora project at GitHub
## Uncomment necessary line, comment out unnecessary, and run the script.
## 2012(c) Michael Galyuk, Pandora, freeware

## Init git on your computer
git config --global user.name "Michael Galyuk"
git config --global user.email robux@mail.ru

## Start new repository
#git init
#git add README.TXT
#git commit -m "first commit"
#git remote rm origin
#git remote add origin https://github.com/Novator/Pandora.git
#git push -u origin master

## Show state
#git status

## Push files from local to repository
#git add --all
git commit -a -m "version 0.1 alfa"
git push -u origin master

## Ignore list. Exclude or remove(!) files
#nano .gitignore
#git rm --cached rubyfull.exe
#git rm rubyfull.exe

## Rename file or directory
#git mv ruby.exe rubyfull.exe

## Getting repository to local directory
#git clone https://github.com/Novator/Pandora.git

## Getting changes from repository to local
#git pull
