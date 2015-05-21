# github-rails

This is the fork of Rails used in github/github.

## Development

    $ git clone https://github.com/github/github-rails
    $ cd github-rails
    $ script/cibuild

All the tests pass, right?

## Merging changes into github/github

0. Make a PR containing your changes
0. In your PR, bump the version number in [`RAILS_VERSION`][] (e.g., from
   `3.2.21.github3` to `3.2.21.github4`) and run `bundle install` to update
   `Gemfile.lock`
0. In github/github, run `script/vendor-rails -b your-branch-name` to pull your
   changes into github/github.

[`RAILS_VERSION`]: RAILS_VERSION
