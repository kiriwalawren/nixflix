#include <ctype.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/random.h>

#include <nettle/pbkdf2.h>
#include <string.h>
#include <unistd.h>

#define DEBUG(...)                                                             \
  if (debug)                                                                   \
  printf(__VA_ARGS__)

int uppercase = 0;
int debug = 0;
size_t salt_len;

static void display_hex(unsigned length, uint8_t *data) {
  unsigned i;

  for (i = 0; i < length / 2; i++) {
    if (uppercase)
      printf("%02X", data[i]);
    else
      printf("%02x", data[i]);
  }

  printf("\n");
}

void str_to_upper(char *str, size_t len) {
  for (size_t i = 0u; i < len; i++) {
    str[i] = toupper(str[i]);
  }
}

uint8_t *hex_decode(char *hex) {
  DEBUG("salt: %s\n", hex);
  size_t size = strlen(hex);
  // 1 byte = 2 hex characters so that means the length in bytes is size / 2
  salt_len = size / 2;
  char *val = malloc(size);
  char *pos = hex;

  for (size_t count = 0; count < size; count++) {
    sscanf(pos, "%2hhx", &val[count]);
    pos += 2;
  }

  return (uint8_t *)val;
}

int main(int argc, char **argv) {
  int opt;

  uint8_t *key = NULL;
  unsigned int iterations = 0;
  size_t length = 0;
  uint8_t *salt = NULL;
  int print_metadata = 1;

  while ((opt = getopt(argc, argv, "k:i:l:vnus::")) != -1) {
    switch (opt) {
    case 'k':
      key = (uint8_t *)optarg;
      break;
    case 'i':
      iterations = strtoul(optarg, NULL, 0);
      break;
    case 'l':
      length = strtoul(optarg, NULL, 0);
      break;
    case 'v':
      debug = 1;
      break;
    case 'n':
      print_metadata = 0;
      break;
    case 'u':
      uppercase = 1;
      break;
    case 's':
      salt = hex_decode(optarg);
      break;
    default:
      fprintf(stderr,
              "Usage: %s -k val -i val -l val [-sval]\n"
              "-k: Key to hash\n"
              "-i: Iterations/rotations of pbkdf2-sha512 algorithm\n"
              "-l: Length of output hash\n"
              "-n: No metadata with hash. Only print hash\n"
              "-v: Verbose\n"
              "-u: Output hash in uppercase\n"
              "-s: The salt to use. If not provided uses random salt (16 "
              "length)\n",
              argv[0]);
      return EXIT_FAILURE;
    }
  }

  if (key == NULL) {
    fprintf(stderr, "No key provided");
    return EXIT_FAILURE;
  }
  if (iterations == 0) {
    fprintf(stderr, "Invalid or no iterations provived");
    return EXIT_FAILURE;
  }
  if (length == 0) {
    fprintf(stderr, "Invalid or no length provived");
    return EXIT_FAILURE;
  }

  // generate salt if none were provided
  if (salt == NULL) {
    DEBUG("Generating random salt...");
    salt_len = 16;
    salt = malloc(salt_len);
    getrandom(salt, salt_len, GRND_RANDOM);
  } else {
    DEBUG("Using provided salt...");
  }

  uint8_t *buffer = malloc(length + 1);

  DEBUG("Key to hash: %s\n", key);
  DEBUG("Iterations: %d\n", iterations);
  DEBUG("Length: %zu\n", length);
  DEBUG("Salt: %.*s\n", (int)salt_len, (char *)salt);

  pbkdf2_hmac_sha512(strlen((char *)key), key, iterations, salt_len, salt,
                     length, buffer);

  if (print_metadata) {
    printf("$PBKDF2-SHA512$iterations=%d$", iterations);
    // salt hex
    for (int i = 0; i < salt_len; i++) {
      printf("%02X", salt[i]);
    }
    printf("$");
  }

  display_hex(length, buffer);

  free(salt);
  free(buffer);
  return EXIT_SUCCESS;
}
