chord
=====

Weird chord implementation using Ruby and EventMachine

Disclaimer
----------

This doesn't yet work — completely. As of now it's possible to create a worthless DHT that doesn't store or retrieve anything yet, and have nodes join that DHT. Nodes will figure out their successor and predecessor, and populate their finger table.

There are several bugs as of now, and this is not even remotely close to production ready.

Usage
-----

Just clone, run bundler to install relevant gems, and run.

```bash
$ git clone https://github.com/punnie/chord
Cloning into 'chord'...

$ bundle
Fetching gem metadata from https://rubygems.org/.......

$ ruby chord.rb -h
Usage: chord.rb [options]
    -j, --join HOST                  One node of the DHT to join (format: host:port)
```

Creating a node that just listens, joins no other node.

```bash
$ ruby chord.rb
```

Creating a node that joins an existing DHT.

```bash
$ ruby chord.rb -j hostname:port
```

Development notes
-----------------

Developed using Ruby 1.9.3, should be 2.0.0 compatible.

License
-------

MIT. See the `LICENSE` file for full description.
