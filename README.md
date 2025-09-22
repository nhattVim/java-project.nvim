### Requirements

- [Java](https://www.java.com/)
- [Maven](https://maven.apache.org/)
- [Gradle](https://gradle.org/)

### Description

Inspired by [pojokcodeid/auto-java-project.nvim](https://github.com/pojokcodeid/auto-java-project.nvim)

### Installation

```lua
-- lua with lazy.nvim
return {
    "nhattVim/java-project.nvim",
    config = true,
    cmd = {
        "NewMavenProject",
        "NewGradleProject",
        "NewSpringBootProject",
    },
}
```
