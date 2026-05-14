#!/usr/bin/env python3

import sys

from specfile import Specfile


def main() -> int:
	if len(sys.argv) != 2:
		print(f"uso: {sys.argv[0]} ARQUIVO.spec", file=sys.stderr)
		return 1

	spec = Specfile(sys.argv[1])
	print(spec.version)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

