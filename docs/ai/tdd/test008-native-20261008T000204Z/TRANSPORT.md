# Current lossless alias resolution

Historical transport-manifest.json, reports and hashes remain immutable. Native TEST008 required five additional short identity aliases in native-aliases.json. Use this directory's recover.py for current proof recovery: it resolves the old19 aliases plus these five aliases transitively, verifies the original bytes/hash, and uses only a matching current Git blob if checkout CRLF altered identity text. Four old colon aliases now traverse their previous hyphen alias to a short leaf. The old historical helper remains preserved as historical evidence; its direct old destination lookup is superseded for these four renamed leaves. No historical hash is replaced with a current hash.

Example: python3 docs/ai/tdd/test008-native-20261008T000204Z/recover.py --root /absolute/current/checkout --path ORIGINAL_NAMED_PATH

Raw native bfea WSL proof is lossless base64; native-bfea-raw.json records the original SHA/byte count and253NULs. Reconstructed raw files belong only in scratch. native-clone.red.log is a classified readable failure excerpt plus complete parsed JSON, not an assertion that its hash equals the original raw log. Native fixture Legacy RED is distinct from the provider implementation, which remains unchanged.
