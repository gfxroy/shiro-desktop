FROM debian:13-slim
ENV DEBIAN_FRONTEND=noninteractive DISPLAY=:88 HOME=/home/shiro-local USER=shiro-local
RUN apt-get update && apt-get install -y --no-install-recommends chromium xvfb openbox xdotool scrot xclip xterm thunar dbus-x11 python3 python3-websocket python3-pil python3-reportlab python3-openpyxl python3-docx poppler-utils fonts-dejavu-core fonts-liberation ca-certificates x11vnc novnc websockify tini && rm -rf /var/lib/apt/lists/* && useradd -m -u 1000 -s /bin/bash shiro-local && mkdir /home/shiro-local/workspace && chown -R 1000:1000 /home/shiro-local
COPY guest.py /opt/shiro/guest.py
COPY start.sh /opt/shiro/start.sh
RUN chmod 755 /opt/shiro/start.sh
USER 1000:1000
EXPOSE 6080
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/shiro/start.sh"]
