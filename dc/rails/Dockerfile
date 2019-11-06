FROM ruby:latest

# We install less and vim to have a couple utilities inside the container,
# though editing should happen mostly in the host.
#
# Active Storage needs mupdf, mupdf-tools, poppler-utils, and ffmpeg.
RUN apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ffmpeg \
    less \
    mupdf \
    mupdf-tools \
    poppler-utils \
    redir \
    sqlite3 \
    vim
