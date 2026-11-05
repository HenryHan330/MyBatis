# 05 动态 SQL

> 动态 SQL = **SQL 里的 if / switch / for**。它是 MyBatis 最有价值的部分，也是「一个 Mapper 顶十个」的原因。

## 0. 为什么需要动态 SQL

需求：多条件查询 —— 用户可能只填品牌，也可能只填价格区间，也可能都不填。

用 JDBC 拼 SQL 会写成这样：

```java
StringBuilder sql = new StringBuilder("select * from t_car where 1 = 1");
if (brand != null && !brand.isEmpty()) sql.append(" and brand = '").append(brand).append("'");
if (minPrice != null) sql.append(" and guide_price >= ").append(minPrice);
// ... 一堆 if，还要处理 and 的位置、空格、注入
```

MyBatis 用标签把这些都包了：**条件成立才拼进去，还会自动处理 `and` / 逗号**。

## 1. `<if>`

```xml
<select id="selectByMultiCondition" resultType="Car">
    select * from t_car where 1 = 1
    <if test="brand != null and brand != ''">
        and brand like concat('%', #{brand}, '%')
    </if>
    <if test="guidePrice != null">
        and guide_price &gt;= #{guidePrice}
    </if>
    <if test="carType != null and carType != ''">
        and car_type = #{carType}
    </if>
</select>
```

**`test` 属性的规则**

- 写的是 **OGNL 表达式**，直接写属性名（`brand`），不能用 `#{}`。
- 字符串判空：`brand != null and brand != ''`。
- 数字只判 `null`：`guidePrice != null`（**别写 `guidePrice != ''`**，数字和空串比较在 OGNL 里会出错）。
- XML 里 `<` 要写成 `&lt;`，或用 `<![CDATA[ < ]]>` 包起来。
- `test` 里只能用 `and` / `or`，**不能用 `&&`**（`&` 在 XML 中是非法字符）。

> 用 `where 1 = 1` 的写法能用但丑，下面换成 `<where>`。

## 2. `<where>`（推荐）

```xml
<select id="selectByMultiCondition2" resultType="Car">
    select * from t_car
    <where>
        <if test="brand != null and brand != ''">
            and brand like concat('%', #{brand}, '%')
        </if>
        <if test="guidePrice != null">
            and guide_price &gt;= #{guidePrice}
        </if>
    </where>
</select>
```

`<where>` 干两件事：

1. **有条件时**才插入 `where` 关键字；
2. **自动去掉第一个条件前面的 `and` 或 `or`**。

> 它只去掉**开头**多余的那个 `and`；如果所有 `if` 都不成立，就没有 `where`，SQL 是 `select * from t_car` —— 合法。

## 3. `<trim>`：`<where>` / `<set>` 的底层实现

```xml
<!-- 等价于 where -->
<trim prefix="WHERE" prefixOverrides="AND |OR ">
    <if test="brand != null and brand != ''">and brand = #{brand}</if>
    <if test="carType != null and carType != ''">and car_type = #{carType}</if>
</trim>
```

| 属性 | 含义 |
| --- | --- |
| `prefix` | 内容非空时，在最前面加上的内容 |
| `suffix` | 内容非空时，在最后面加上的内容 |
| `prefixOverrides` | 内容以这些字符串**开头**时，把它们去掉 |
| `suffixOverrides` | 内容以这些字符串**结尾**时，把它们去掉 |

```xml
<!-- 等价于 set -->
<trim prefix="SET" suffixOverrides=",">
    <if test="brand != null">brand = #{brand},</if>
    <if test="carType != null">car_type = #{carType},</if>
</trim>
```

> 记住这两个等价关系，读别人代码就不慌了：
> `<where>` = `<trim prefix="WHERE" prefixOverrides="AND |OR ">`
> `<set>` = `<trim prefix="SET" suffixOverrides=",">`

## 4. `<set>`：动态更新

```xml
<update id="updateByCondition">
    update t_car
    <set>
        <if test="carNum != null and carNum != ''">car_num = #{carNum},</if>
        <if test="brand != null and brand != ''">brand = #{brand},</if>
        <if test="guidePrice != null">guide_price = #{guidePrice},</if>
    </set>
    where id = #{id}
</update>
```

`<set>` 干两件事：有条件时插入 `set` 关键字；**自动去掉最后多余的逗号**。

> **最大的坑**：所有 `if` 都不成立时，`<set>` 什么都不输出，SQL 变成 `update t_car where id = ?`
> ⇒ **语法错误**。所以 update 前必须在 service 层校验「至少有一个字段要改」。

## 5. `<choose>` / `<when>` / `<otherwise>`

相当于 Java 的 `switch`，**只会命中一个分支**（和一堆 `if` 不同）。

```xml
<select id="selectByChoose" resultType="Car">
    select * from t_car
    <where>
        <choose>
            <when test="brand != null and brand != ''">
                brand = #{brand}
            </when>
            <when test="carType != null and carType != ''">
                car_type = #{carType}
            </when>
            <otherwise>
                guide_price &gt; 30
            </otherwise>
        </choose>
    </where>
</select>
```

使用场景：同一个查询，按不同优先级取条件（命中即止）。

## 6. `<foreach>`：循环

| 属性 | 说明 |
| --- | --- |
| `collection` | 要遍历的集合：List 未命名时用 `list`，数组用 `array`，Map 用 `map`，**有 `@Param` 时用注解名** |
| `item` | 每次循环的元素名 |
| `index` | 循环下标（List 是索引，Map 是 key） |
| `open` / `close` | 循环开始前 / 结束后拼什么 |
| `separator` | 元素之间的分隔符 |

### 6.1 批量删除：`in`

```xml
<delete id="deleteBatch">
    delete from t_car where id in
    <foreach collection="ids" item="id" open="(" separator="," close=")">
        #{id}
    </foreach>
</delete>
```

```java
int deleteBatch(@Param("ids") List<Long> ids);
```

生成的 SQL：`delete from t_car where id in ( ? , ? , ? )`

### 6.2 批量插入：`values (...),(...)`

```xml
<insert id="insertBatch">
    insert into t_car(car_num, brand, guide_price, produce_time, car_type) values
    <foreach collection="cars" item="car" separator=",">
        (#{car.carNum}, #{car.brand}, #{car.guidePrice}, #{car.produceTime}, #{car.carType})
    </foreach>
</insert>
```

```java
int insertBatch(@Param("cars") List<Car> cars);
```

> 不加 `@Param` 时，单个 `List` 参数的 `collection` 必须写 `list`（不是 `cars`）。
> 批量插入效率远高于循环单条 `insert`，但 SQL 长度受 `max_allowed_packet` 限制，**建议每 500~1000 条一批**。

### 6.3 `foreach` 里用 `${}` 拼列名（少见）

```xml
<select id="selectByColumns" resultType="Car">
    select * from t_car where
    <foreach collection="columns" item="col" separator=" and ">
        ${col} is not null
    </foreach>
</select>
```

列名必须用 `${}`（`?` 不能代替标识符），同时**必须做白名单校验**，否则就是注入。

## 7. `<sql>` + `<include>`：SQL 片段复用

```xml
<!-- 定义片段 -->
<sql id="baseColumns">
    id, car_num, brand, guide_price, produce_time, car_type
</sql>

<!-- 引用片段 -->
<select id="selectById" resultType="Car">
    select <include refid="baseColumns"/> from t_car where id = #{id}
</select>

<select id="selectAll" resultType="Car">
    select <include refid="baseColumns"/> from t_car
</select>
```

**进阶：`<include>` 传参**（片段内部用 `${}` 取值，`#{}` 在这里不行）

```xml
<sql id="baseColumns">
    <if test="alias != null">${alias}.</if>id, car_num
</sql>

<select id="selectWithAlias" resultType="Car">
    select <include refid="baseColumns">
                <property name="alias" value="c"/>
           </include>
    from t_car c
</select>
```

## 8. 综合案例：多条件 + 排序 + 分页

```xml
<select id="selectByCondition" resultMap="carResultMap">
    select <include refid="baseColumns"/>
    from t_car
    <where>
        <if test="brand != null and brand != ''">
            and brand like concat('%', #{brand}, '%')
        </if>
        <if test="minPrice != null">
            and guide_price &gt;= #{minPrice}
        </if>
        <if test="maxPrice != null">
            and guide_price &lt;= #{maxPrice}
        </if>
        <if test="carType != null and carType != ''">
            and car_type = #{carType}
        </if>
        <if test="ids != null and ids.size() > 0">
            and id in
            <foreach collection="ids" item="id" open="(" separator="," close=")">
                #{id}
            </foreach>
        </if>
    </where>
    <choose>
        <when test="orderBy == 'price'">order by guide_price desc</when>
        <when test="orderBy == 'time'">order by produce_time desc</when>
        <otherwise>order by id asc</otherwise>
    </choose>
    limit #{offset}, #{pageSize}
</select>
```

## 9. 动态 SQL 踩坑清单

| 坑 | 说明 |
| --- | --- |
| `test` 里用 `#{}` | 错，应直接写属性名：`test="brand != null"` |
| `test` 里用 `&&` 或 `<` | XML 中非法，用 `and` / `&lt;` |
| 字符串判空只写 `!= null` | 空串 `""` 也会拼进 SQL，要加 `and brand != ''` |
| `<set>` 里全为空 | SQL 变成 `update ... where`，语法错误 |
| `<foreach>` 的 `collection` 写错 | List 未命名时是 `list`，数组是 `array` |
| 用了 `@Param("ids")` 还写 `list` | 必须写 `ids` |
| `<where>` 里第一个条件是 `or` | 能去掉，但语义上容易查出全表 |
| `test` 里写 `ids.size() > 0` 报错 | 用 `ids != null and ids.size() > 0`，注意判空在前 |

