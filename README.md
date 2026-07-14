# Wilbertils

Wilberforce project utility belt

## Installation

Add this line to your application's Gemfile:

    gem 'wilbertils'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install wilbertils

## Live Local Wilbertils Updates in Docker
Builds will pickup the current dev wilbertils with the COPY command, no changes required.
Run docker commands with local wilbertils rather than the gem add `--env DEVELOPMENT=true` to commands (bundling local updates to wilbertils versions for example):
`docker compose run --env DEVELOPMENT=true wilberforce bundle lock --conservative --update aws-sdk`

## Usage

TODO: Write usage instructions here

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Ruby Version

Wilbertils should work with any version of Ruby from the other MF repositories. We can not pin it's version down exactly as sometimes the projects are slightly out of sync.
