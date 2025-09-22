https://github.com/user-attachments/assets/b0c7c483-a11f-4de5-bef3-78b59ca21a1f

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
