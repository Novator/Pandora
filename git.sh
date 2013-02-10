#!/bin/sh

## These hot commands of Git are using for maintenance Pandora project at GitHub
## Uncomment necessary line, comment out unnecessary, and run the script.
## 2012(c) Michael Galyuk, Pandora, freeware
## RU: Популярные команды git, используемые для сопровождения Пандоры на Гитхабе
## RU: Раскомментируй нужные строки, закомментируй ненужные, и запусти скрипт.

## Init git on your computer
## (Change name and email!)
#git config --global user.name "Michael Galyuk"
#git config --global user.email ironsoft@mail.ru
#git config --global color.ui true
#git config --global core.autocrlf input
#git config --global core.safecrlf true
#git config --global credential.helper cache
#git config credential.helper 'cache --timeout=3600'

## Start new repository
#git init
#git add README.TXT
#git commit -m "first commit"
#git remote rm origin
#git remote add origin https://github.com/Novator/Pandora.git
#git push -u origin master

## Show state
#git status
#git remote -v
#git branch -v
#git diff

## Push files from local to repository
#git add --all
git commit -a -m "version 0.1 alfa"
git push -u origin master

##Modify last commit
#git commit --amend

## Ignore list. Exclude or remove(!) files
#nano .gitignore
#git rm --cached rubyfull.exe
#git rm rubyfull.exe

## Rename file or directory
#git mv ruby.exe rubyfull.exe

## Getting repository to local directory
#git clone https://github.com/Novator/Pandora.git

## Getting changes from repository to local (with or without merge)
#git pull
#git fetch

## Merge pull from another brunch
#git pull https://github.com/rc5hack/Pandora master

##Delete history of commits
##(you need to modify "pick" to "s" in all lines besides first)
#git reflog
#git rebase -i HEAD~4
#git push -f

##Pack git objects
#git gc

##Create branch, move to it, or both
#git branch testing
#git checkout testing
#git checkout -b 'testing'

##Merge branch, see conflits, add corrects, and delete unused branch
#git checkout master
#git merge testing
#git status
#git add pandora.rb
#git commit
#git branch --merged
#git branch --no-merged
#git branch -d testing

