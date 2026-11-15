# Boring Notch Extension Exception

Version 1.0

This is an additional permission under section 7 of the GNU General Public License,
version 3 ("GPLv3"). It applies to Boring Notch, which is otherwise licensed under
GPLv3 as described in `LICENSE`.

## Definitions

"Boring Notch" means the program in this repository, including any version modified
by its copyright holders, released under GPLv3 with this exception.

"Extension Interface" means the C functions, data formats, manifest fields and
commands documented in `docs/extension-api.h` and `docs/extensions.md`, by which
Boring Notch loads an extension and exchanges data with it.

"Extension" means a separately packaged bundle that:

1. communicates with Boring Notch only through the Extension Interface, and
2. contains no code copied from Boring Notch and is not based on Boring Notch's
   source code, apart from declarations of the Extension Interface itself (such as
   function signatures and data structure layouts) needed to implement it.

## Permission

As a special exception, the copyright holders of Boring Notch give you permission to
load, run and distribute Boring Notch together with any Extension, and to distribute
an Extension, under terms of your choice for the Extension, including terms that
do not allow modification or redistribution and that keep its source code private.
This applies even though Boring Notch and the Extension run in the same process and
exchange data while running.

The Extension is not required to be licensed under GPLv3 because of this
combination. Boring Notch itself remains licensed under GPLv3, and you must still
follow GPLv3 for Boring Notch and for any modified version of it that you distribute.

## Limits

This exception does not apply to:

- code copied from Boring Notch into an Extension, or code based on it, which stays
  under GPLv3;
- changes to Boring Notch itself, including changes that add to or change the
  Extension Interface, which stay under GPLv3.

## Modified versions

If you modify Boring Notch, you may extend this exception to your modified version,
but you are not required to. If you do not wish to, remove this exception from your
version.
