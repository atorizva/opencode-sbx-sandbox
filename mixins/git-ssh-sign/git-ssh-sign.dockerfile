# syntax=docker/dockerfile:1

FROM scratch

COPY --chmod=0755 ssh-signing-key-command /home/agent/.config/git/ssh-signing-key-command
