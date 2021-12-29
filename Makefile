
lint:
	swiftlint .

fmt:
	swiftformat --swiftversion 5 .
	swiftlint . --fix
