## (Future) Removal of API version 1

The ACME API version 1 was never really standardized and was only supported by Let's Encrypt. Even though the protocol specification was public,
it wasn't really friendly to be integrated into existing CA systems so initial adoption was basically non-existant.

ACME version 2 is being designed to overcome these issues by becoming an official IETF standard and supporting a more traditional approach of account
and order management in the backend, making it friendlier to integrate into existing systems centered around those. It has since become a semi-stable IETF
standard draft which only ever got two breaking changes, Content-Type enforcement and `POST-as-GET`, the latter being announced in October 2018 to be enforced
by November 2019. See https://datatracker.ietf.org/wg/acme/documents/ for a better insight into the draft and its changes.

Next to backend changes that many users won't really care about ACME v2 has all of the features ACME v1 had, but also some additional new features like
e.g. support for [wildcard certificates](domains_txt.md#wildcards).

Since ACME v2 is basically to be considered stable and ACME v1 has no real benefits over v2, there doesn't seem to be much of a reason to keep the old
protocol around, but since there actually are a few Certificate Authorities and resellers that implemented the v1 protocol and didn't yet make the change
to v2, so dehydrated still supports the old protocol for now.

Please keep in mind that support for the old ACME protocol version 1 might get removed at any point of bigger inconvenience, e.g. on code changes that
would require a lot of work or ugly workarounds to keep both versions supported.
