# WHY BUILD CUSTOM IMAGES AND NOT JUST UPDATE THE OFFICIAL ONES?

Source: [11notes/RTFM](https://github.com/11notes/RTFM/blob/main/linux/container/image/custom.md)

*People are quick to tell other developers to just create a PR (pull request) like on GitHub, but what are the actual implications of this and why is it rarely done?*

**TL;DR:** Time. It costs an immense amount of time to convince others to go rootless or even distroless and more often than not you get huge pushback so in the end, nothing changes but you wasted hours. Hours that could have been used to create the better image in the first place, instead of battling with other devs.

# SYNOPSIS

People who don't write code or barely any code often quickly point out that a simple PR to the original image would have been the better approach than creating another custom image for the same app. They see the redundancy and automatically think this is bad. They do not see that the same problem can be approached from different angles.

# BUT WHY NOT UPDATE THE ORIGINAL IMAGE WITH THESE CHANGES?

That's very simple: **It requires a lot of effort.** Most changes to a container image to repackage an app as a custom image are severe. This means they can't just be pushed to the original image without disrupting how the original image is created. Many things in the original image creation process (CI/CD) would have to be changed and these many, many changes are seldom seen as a benefit.

Think the debate of rootless and distroless. Many developers don't see a problem in running their app as root, they even see it as a benefit, so that every user can use it, without worrying about file permissions or kernel restrictions. Spending many hours to create a custom CI/CD process to make their original container image better, only for these changes to be rejected is a waste of everyone's time.

The next issue is politics. Many projects do not allow changes from outsiders, by default. Others require you to sign off on your contribution, meaning you will not get credited for all the work you did. Why fight political battles in why rootless is better when you can instead just create your rootless image yourself, without everyone fighting you along the way? People and especially developers do not like change.

# PERSONAL EXPERIENCE

I've had my fair share of all these political interactions. I've had developers denying my PR because the indent was wrong or because I added comments in a different style that they wanted. Some started the old debate of Alpine vs. Debian instead of focusing a lightweight image for their users. Code was never accepted as it was. It was always scrutinized for reasons that are either pure vanity or pride. These hundreds of hours wasted are proof that creating a simple PR request to make the original image better, is a lie.

# CONCLUSION

The next time you see someone pointing out to *"just create a PR"* think about how hard this actually is and what a can of worms in terms of politics this opens.

**If you want things done right, you have to do it yourself.**
